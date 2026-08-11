//
//  ProjectsManager.swift
//  boringNotch
//
//  Launches per-project run commands (typically `make` targets) and lets the
//  user stop them again. Each command runs in its own login shell; on stop we
//  walk and kill the whole descendant process tree so dev servers spawned by
//  `make` don't survive.
//

import AppKit
import Combine
import Defaults
import Foundation

// TEMP diagnostic: trace the run/stop path to a file for verification.
func projDebug(_ s: String) {
    let line = "\(Date().timeIntervalSince1970) \(s)\n"
    let url = URL(fileURLWithPath: "/tmp/projects_debug.log")
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        if let d = line.data(using: .utf8) { h.write(d) }
        try? h.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

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

    // IDs whose launcher process has exited, but whose actual service is still
    // detected alive via its last-known port (e.g. a `make run` target that
    // intentionally backgrounds its real server with `nohup ... &` and exits
    // immediately). These stay in `runningIDs` so the UI keeps showing them as
    // running with a Stop button; `stop()` handles them differently since
    // there's no live process tree left to kill directly.
    @Published private(set) var headlessIDs: Set<UUID> = []

    // Listening TCP ports detected for each running project's process tree.
    @Published private(set) var portsByProject: [UUID: [Int]] = [:]

    // Captured stdout+stderr per project (capped).
    @Published private(set) var logsByProject: [UUID: String] = [:]

    private var processes: [UUID: Process] = [:]
    private var logPipes: [UUID: Pipe] = [:]
    private var portTimer: Timer?
    private let logCharLimit = 16_000

    // "id:port" pairs already auto-opened, so we open each port only once.
    private var autoOpened: Set<String> = []

    private init() {}

    // MARK: - Public controls

    func isRunning(_ id: UUID) -> Bool { runningIDs.contains(id) }

    func toggle(_ config: ProjectRunConfig) {
        projDebug("toggle '\(config.name)' isRunning=\(isRunning(config.id))")
        isRunning(config.id) ? stop(config.id) : run(config)
    }

    func run(_ config: ProjectRunConfig) {
        projDebug("run '\(config.name)' dir=\(config.directory) cmd=\(config.command)")
        guard !isRunning(config.id) else {
            projDebug("run aborted: already running")
            return
        }
        guard FileManager.default.fileExists(atPath: config.directory) else {
            projDebug("run aborted: directory does not exist: \(config.directory)")
            print("ProjectsManager: directory does not exist: \(config.directory)")
            return
        }

        let id = config.id
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Login shell so PATH/toolchains resolve like the user's terminal.
        process.arguments = ["-lc", "cd \(Self.shellQuote(config.directory)) && \(config.command)"]
        process.currentDirectoryURL = URL(fileURLWithPath: config.directory)

        // Capture stdout + stderr into a live, capped buffer for the log viewer.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.appendLog(id, chunk) }
        }

        logsByProject[id] = ""
        process.terminationHandler = { [weak self] proc in
            projDebug("'\(config.name)' launcher terminated, status=\(proc.terminationStatus) reason=\(proc.terminationReason.rawValue)")
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self else { return }
                self.appendLog(id, "\n— launcher exited (status \(proc.terminationStatus)) —\n")
                self.processes[id] = nil
                self.logPipes[id] = nil
                self.handleLauncherExit(id: id, name: config.name)
            }
        }

        do {
            try process.run()
            processes[id] = process
            logPipes[id] = pipe
            runningIDs.insert(id)
            startPortPolling()
            projDebug("run succeeded: pid=\(process.processIdentifier)")
        } catch {
            projDebug("run FAILED to launch: \(error)")
            print("ProjectsManager: failed to launch \(config.name): \(error)")
            appendLog(id, "Failed to launch: \(error.localizedDescription)\n")
        }
    }

    /// Called when the launcher process exits. If we'd already detected a
    /// listening port for this project, re-check it before declaring the
    /// project stopped — some `run` targets background their real server and
    /// exit immediately on purpose (e.g. `nohup ... &`), in which case the
    /// service is still running, just orphaned from the process tree we were
    /// watching.
    private func handleLauncherExit(id: UUID, name: String) {
        let lastPorts = portsByProject[id] ?? []
        guard !lastPorts.isEmpty else {
            finalizeStop(id)
            return
        }
        Task.detached { [weak self] in
            let alive = Self.anyPortListening(lastPorts)
            await MainActor.run {
                guard let self else { return }
                if alive {
                    projDebug("'\(name)' launcher exited but port(s) \(lastPorts) still listening — treating as backgrounded")
                    self.headlessIDs.insert(id)
                    self.appendLog(id, "Service still running in the background on port(s) \(lastPorts).\n")
                    self.startPortPolling()
                } else {
                    self.finalizeStop(id)
                }
            }
        }
    }

    private func finalizeStop(_ id: UUID) {
        runningIDs.remove(id)
        headlessIDs.remove(id)
        portsByProject[id] = nil
        autoOpened = autoOpened.filter { !$0.hasPrefix("\(id):") }
        stopPortPollingIfIdle()
    }

    /// Stop then relaunch a project a moment later.
    func restart(_ config: ProjectRunConfig) {
        stop(config.id)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            run(config)
        }
    }

    private func appendLog(_ id: UUID, _ chunk: String) {
        var current = logsByProject[id] ?? ""
        current += chunk
        if current.count > logCharLimit {
            current = String(current.suffix(logCharLimit))
        }
        logsByProject[id] = current
    }

    func clearLogs(_ id: UUID) {
        logsByProject[id] = ""
    }

    func stop(_ id: UUID) {
        let config = Defaults[.projectRunConfigs].first { $0.id == id }
        projDebug("stop '\(config?.name ?? "?")' headless=\(headlessIDs.contains(id))")

        // Prefer the project's own stop lifecycle when it has one (e.g. a
        // Makefile `stop:` target) — this is the only thing that can actually
        // reach a detached/backgrounded service (one whose launcher already
        // exited and orphaned it), since there's no process tree left for us
        // to walk and kill directly in that case.
        if let directory = config?.directory, Self.hasMakeStopTarget(in: directory) {
            Task.detached { await Self.runMakeStop(directory: directory) }
        }

        // Also kill the tracked process tree if we still have a live handle —
        // covers `run` targets that stay in the foreground (the original,
        // simpler case this was first built for).
        if let process = processes[id], process.processIdentifier > 0 {
            let rootPID = process.processIdentifier
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
        }

        // Reflect the stop immediately; terminationHandler will also fire for
        // any live process.
        finalizeStop(id)
        processes[id] = nil
    }

    func stopAll() {
        for id in runningIDs { stop(id) }
    }

    /// Open http://localhost:<port> in the default browser.
    func openPort(_ port: Int) {
        guard let url = URL(string: "http://localhost:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Port detection

    private func startPortPolling() {
        guard portTimer == nil else { return }
        refreshPorts()
        let t = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPorts() }
        }
        RunLoop.main.add(t, forMode: .common)
        portTimer = t
    }

    private func stopPortPollingIfIdle() {
        guard runningIDs.isEmpty else { return }
        portTimer?.invalidate()
        portTimer = nil
    }

    /// For each running project, find the listening TCP ports owned by any
    /// process in its tree (the dev server is a descendant of the launch shell).
    /// Headless projects (launcher already exited, service backgrounded) have
    /// no process tree to walk anymore, so their last-known ports are re-checked
    /// directly instead — and cleared if they finally go silent.
    private func refreshPorts() {
        let liveSnapshot: [(UUID, Int32)] = runningIDs.subtracting(headlessIDs).compactMap { id in
            guard let p = processes[id], p.processIdentifier > 0 else { return nil }
            return (id, p.processIdentifier)
        }
        let headlessSnapshot: [(UUID, [Int])] = headlessIDs.compactMap { id in
            guard let ports = portsByProject[id], !ports.isEmpty else { return nil }
            return (id, ports)
        }
        guard !liveSnapshot.isEmpty || !headlessSnapshot.isEmpty else { return }

        Task.detached {
            var liveResult: [UUID: [Int]] = [:]
            for (id, root) in liveSnapshot {
                let pids = Self.descendants(of: root) + [root]
                liveResult[id] = Self.listeningPorts(forPIDs: pids)
            }
            var headlessAlive: [UUID: Bool] = [:]
            for (id, ports) in headlessSnapshot {
                headlessAlive[id] = Self.anyPortListening(ports)
            }
            await MainActor.run {
                let autoOpen = Defaults[.projectsAutoOpenPort]
                for (id, ports) in liveResult where self.runningIDs.contains(id) {
                    self.portsByProject[id] = ports
                    guard autoOpen, let first = ports.first else { continue }
                    let key = "\(id):\(first)"
                    if !self.autoOpened.contains(key) {
                        self.autoOpened.insert(key)
                        self.openPort(first)
                    }
                }
                for (id, alive) in headlessAlive where !alive {
                    projDebug("headless project \(id) ports went silent — marking stopped")
                    self.finalizeStop(id)
                }
            }
        }
    }

    /// Listening TCP ports for the given PIDs via `lsof -a -p <pids>`.
    private nonisolated static func listeningPorts(forPIDs pids: [Int32]) -> [Int] {
        guard !pids.isEmpty else { return [] }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", pids.map(String.init).joined(separator: ",")]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return [] }

        var ports = Set<Int>()
        for line in out.components(separatedBy: .newlines).dropFirst() {
            let cols = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard cols.count >= 9 else { continue }
            // NAME column e.g. "*:3000" or "127.0.0.1:3000"
            let nameFirst = cols[8...].joined(separator: " ").components(separatedBy: .whitespaces)[0]
            if let portStr = nameFirst.components(separatedBy: ":").last, let port = Int(portStr) {
                ports.insert(port)
            }
        }
        return ports.sorted()
    }

    /// True if anything is currently listening on any of the given TCP ports.
    private nonisolated static func anyPortListening(_ ports: [Int]) -> Bool {
        guard !ports.isEmpty else { return false }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        let portArg = ports.map(String.init).joined(separator: ",")
        process.arguments = ["-t", "-nP", "-iTCP:\(portArg)", "-sTCP:LISTEN"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return false }
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the project's Makefile defines a `stop:` target, so we know it
    /// has its own proper shutdown lifecycle (reading a pid file etc.) that we
    /// should defer to rather than guessing at how to kill it ourselves.
    private nonisolated static func hasMakeStopTarget(in directory: String) -> Bool {
        let makefileURL = URL(fileURLWithPath: directory).appendingPathComponent("Makefile")
        guard let content = try? String(contentsOf: makefileURL, encoding: .utf8) else { return false }
        return content.range(of: #"(?m)^stop\s*:"#, options: .regularExpression) != nil
    }

    /// Runs `make stop` in the project directory and waits for it to finish.
    private nonisolated static func runMakeStop(directory: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "cd \(shellQuote(directory)) && make stop"]
            var resumed = false
            process.terminationHandler = { _ in
                guard !resumed else { return }
                resumed = true
                cont.resume()
            }
            do {
                try process.run()
            } catch {
                guard !resumed else { return }
                resumed = true
                cont.resume()
            }
        }
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
