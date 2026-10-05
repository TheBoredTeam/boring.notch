//
//  DevelopmentEnvironmentDetector.swift
//  boringNotch
//
//  Detects running IDEs, build tools, terminal tasks and local dev servers
//  using process names and loopback port probes only (no file access).
//

import AppKit
import ApplicationServices
import Darwin
import Network

struct DevServer: Equatable, Hashable {
    let port: UInt16
    let label: String
}

struct DevEnvironment: Equatable {
    var ides: [String] = []
    var buildTool: String? = nil
    var tasks: [String] = []
    var servers: [DevServer] = []
}

struct DevelopmentEnvironmentDetector {
    private static let ideBundles: [String: String] = [
        "com.apple.dt.Xcode": "Xcode",
        "com.microsoft.VSCode": "VS Code",
        "com.microsoft.VSCodeInsiders": "VS Code Insiders",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.exafunction.windsurf": "Windsurf",
        "dev.zed.Zed": "Zed",
        "com.jetbrains.intellij": "IntelliJ",
        "com.jetbrains.pycharm": "PyCharm",
        "com.jetbrains.WebStorm": "WebStorm",
        "com.google.android.studio": "Android Studio",
        "com.sublimetext.4": "Sublime Text",
    ]

    private static let buildProcesses: Set<String> = [
        "xcodebuild", "swift-build", "swift-frontend", "swiftc", "cargo", "rustc",
        "gradle", "tsc", "make", "cmake", "ninja", "clang",
    ]

    private static let taskProcesses: [String: String] = [
        "npm": "npm", "yarn": "yarn", "pnpm": "pnpm", "node": "node", "bun": "bun", "deno": "deno",
        "python3": "python", "python": "python", "cargo": "cargo", "go": "go", "docker": "docker",
        "pytest": "pytest", "jest": "jest", "vite": "vite", "ruby": "ruby", "swift-test": "swift test",
    ]

    private static let serverPorts: [UInt16: String] = [
        3000: "Node / Next", 3001: "Node", 4200: "Angular", 4321: "Astro",
        5173: "Vite", 5174: "Vite", 8000: "Python / Django", 8080: "HTTP", 8888: "Jupyter",
        9000: "HTTP", 1313: "Hugo", 4000: "Jekyll / Phoenix",
    ]

    func detect(includeServers: Bool) async -> DevEnvironment {
        var env = await Task.detached(priority: .utility) { Self.scanProcesses() }.value
        if includeServers { env.servers = await Self.probeServers() }
        return env
    }

    /// Names of windows of running IDEs (requires Accessibility permission; empty otherwise).
    @MainActor
    static func ideWindowTitles() -> [String] {
        guard AXIsProcessTrusted() else { return [] }
        var titles: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, ideBundles[id] != nil else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for window in windows {
                var title: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success,
                   let s = title as? String { titles.append(s) }
            }
        }
        return titles
    }

    // MARK: - Processes

    private static func scanProcesses() -> DevEnvironment {
        var env = DevEnvironment()

        let running = NSWorkspace.shared.runningApplications
        var ides = Set<String>()
        for app in running {
            if let id = app.bundleIdentifier, let name = ideBundles[id] { ides.insert(name) }
        }
        env.ides = ides.sorted()

        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return env }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard got > 0 else { return env }

        var build: String?
        var tasks = Set<String>()
        var buffer = [CChar](repeating: 0, count: 64)
        for pid in pids.prefix(Int(got)) where pid > 0 {
            let len = proc_name(pid, &buffer, UInt32(buffer.count))
            guard len > 0 else { continue }
            let name = String(cString: buffer)
            if build == nil, buildProcesses.contains(name) { build = name }
            if let label = taskProcesses[name] { tasks.insert(label) }
        }
        env.buildTool = build
        env.tasks = Array(tasks.sorted().prefix(4))
        return env
    }

    // MARK: - Dev servers

    private static func probeServers() async -> [DevServer] {
        await withTaskGroup(of: DevServer?.self) { group in
            for (port, label) in serverPorts {
                group.addTask { await isListening(port) ? DevServer(port: port, label: label) : nil }
            }
            var found: [DevServer] = []
            for await server in group { if let server { found.append(server) } }
            return found.sorted { $0.port < $1.port }
        }
    }

    private static func isListening(_ port: UInt16) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: "127.0.0.1", port: nwPort, using: .tcp)
            let gate = OnceGate()
            let finish: @Sendable (Bool) -> Void = { result in
                guard gate.pass() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled, .waiting: finish(false)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { finish(false) }
        }
    }
}

private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func pass() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
