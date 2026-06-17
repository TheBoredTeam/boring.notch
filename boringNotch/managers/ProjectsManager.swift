//
//  ProjectsManager.swift
//  boringNotch
//
//  Launches per-project run commands (typically `make` targets) and lets the
//  user stop them again. Each command runs in its own login shell; on stop we
//  walk and kill the whole descendant process tree so dev servers spawned by
//  `make` don't survive.
//

import Combine
import Defaults
import Foundation

// A single runnable command bound to a project directory.
struct ProjectRunConfig: Codable, Defaults.Serializable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var directory: String   // absolute path to the project folder
    var command: String     // e.g. "make", "make run", "make dev"
}

@MainActor
final class ProjectsManager: ObservableObject {
    static let shared = ProjectsManager()

    // IDs of configs whose process is currently running.
    @Published private(set) var runningIDs: Set<UUID> = []

    private var processes: [UUID: Process] = [:]

    private init() {}

    // MARK: - Public controls

    func isRunning(_ id: UUID) -> Bool { runningIDs.contains(id) }

    func toggle(_ config: ProjectRunConfig) {
        isRunning(config.id) ? stop(config.id) : run(config)
    }

    func run(_ config: ProjectRunConfig) {
        guard !isRunning(config.id) else { return }
        guard FileManager.default.fileExists(atPath: config.directory) else {
            print("ProjectsManager: directory does not exist: \(config.directory)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Login shell so PATH/toolchains resolve like the user's terminal.
        process.arguments = ["-lc", "cd \(Self.shellQuote(config.directory)) && \(config.command)"]
        process.currentDirectoryURL = URL(fileURLWithPath: config.directory)

        let id = config.id
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.runningIDs.remove(id)
                self?.processes[id] = nil
            }
        }

        do {
            try process.run()
            processes[id] = process
            runningIDs.insert(id)
        } catch {
            print("ProjectsManager: failed to launch \(config.name): \(error)")
        }
    }

    func stop(_ id: UUID) {
        guard let process = processes[id] else {
            runningIDs.remove(id)
            return
        }
        let rootPID = process.processIdentifier
        guard rootPID > 0 else {
            runningIDs.remove(id)
            processes[id] = nil
            return
        }

        Task.detached {
            // Children-first so parents don't respawn them, root last.
            let tree = Self.descendants(of: rootPID) + [rootPID]
            for pid in tree { _ = Darwin.kill(pid, SIGTERM) }

            // Give them a moment, then SIGKILL anything still alive.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for pid in tree where Darwin.kill(pid, 0) == 0 {
                _ = Darwin.kill(pid, SIGKILL)
            }
        }

        // Reflect the stop immediately; terminationHandler will also fire.
        runningIDs.remove(id)
    }

    func stopAll() {
        for id in runningIDs { stop(id) }
    }

    // MARK: - Process tree helpers

    /// All descendant PIDs of `pid`, deepest first.
    private nonisolated static func descendants(of pid: Int32) -> [Int32] {
        var result: [Int32] = []
        for child in directChildren(of: pid) {
            result.append(contentsOf: descendants(of: child))
            result.append(child)
        }
        return result
    }

    private nonisolated static func directChildren(of pid: Int32) -> [Int32] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", "\(pid)"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let out = String(data: data, encoding: .utf8) else { return [] }
            return out.split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        } catch {
            return []
        }
    }

    private nonisolated static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
