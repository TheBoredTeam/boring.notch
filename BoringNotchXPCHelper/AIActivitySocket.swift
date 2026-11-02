import Darwin
import Foundation

enum AIActivitySocket {
    // An explicit private namespace lets independently signed development builds
    // and integration tests coexist without stealing the production listener.
    static var directory: String {
        ProcessInfo.processInfo.environment["BORING_NOTCH_AI_SOCKET_DIRECTORY"] ?? "/tmp/boring-notch-ai-\(getuid())"
    }
    static var path: String { directory + "/events.sock" }
    static let maximumBytes = 16_384

    static func address(for path: String = path) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }

    static func sameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }

    static func configure(_ fd: Int32) {
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    static func connect(socketPath: String = path) -> Int32? {
        guard var address = address(for: socketPath) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        configure(fd)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, sameUser(fd) else { close(fd); return nil }
        return fd
    }
}

final class AIActivitySocketListener {
    private var source: DispatchSourceRead?
    private var socketIdentity: (dev_t, ino_t)?
    private let queue = DispatchQueue(label: "boringnotch.ai.socket", qos: .utility)
    private let onEvent: (Data) -> Void
    private let directory: String
    private var path: String { directory + "/events.sock" }

    init(directory: String = AIActivitySocket.directory, onEvent: @escaping (Data) -> Void) {
        self.directory = directory
        self.onEvent = onEvent
    }

    var isAvailable: Bool {
        guard source != nil, let (device, inode) = socketIdentity else { return false }
        var info = stat()
        return lstat(path, &info) == 0 && info.st_dev == device && info.st_ino == inode
    }

    func start() throws {
        if source != nil { return }
        let fm = FileManager.default
        var directoryInfo = stat()
        if lstat(directory, &directoryInfo) != 0 {
            try fm.createDirectory(atPath: directory, withIntermediateDirectories: false,
                                   attributes: [.posixPermissions: 0o700])
        }
        guard lstat(directory, &directoryInfo) == 0,
              directoryInfo.st_uid == getuid(), directoryInfo.st_mode & S_IFMT == S_IFDIR else {
            throw SocketError.invalidDirectory
        }
        chmod(directory, 0o700)
        if let existing = AIActivitySocket.connect(socketPath: path) { close(existing); throw SocketError.alreadyRunning }
        var old = stat()
        if lstat(path, &old) == 0 {
            guard old.st_uid == getuid(), old.st_mode & S_IFMT == S_IFSOCK else { throw SocketError.invalidDirectory }
            unlink(path)
        }
        guard var address = AIActivitySocket.address(for: path) else { throw SocketError.invalidDirectory }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.unavailable }
        AIActivitySocket.configure(fd)
        let previousMask = umask(0o077)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previousMask)
        guard bound == 0, listen(fd, 32) == 0 else { close(fd); throw SocketError.unavailable }
        chmod(path, 0o600)
        var info = stat()
        if lstat(path, &info) == 0 { socketIdentity = (info.st_dev, info.st_ino) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptEvents(fd) }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        if let (device, inode) = socketIdentity {
            var info = stat()
            if lstat(path, &info) == 0, info.st_dev == device, info.st_ino == inode {
                unlink(path)
            }
        }
        socketIdentity = nil
    }

    private func acceptEvents(_ listener: Int32) {
        // Bound work per wakeup; a misbehaving local process cannot allocate an unbounded queue.
        for _ in 0..<32 {
            let fd = accept(listener, nil, nil)
            if fd < 0 { return }
            // Darwin hands accepted sockets the listener's O_NONBLOCK. Clear it so recv waits for a
            // client that connected but has not sent yet (bounded by the receive timeout) instead of
            // returning EAGAIN and silently dropping the event.
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
            AIActivitySocket.configure(fd)
            defer { close(fd) }
            guard AIActivitySocket.sameUser(fd) else { continue }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 2048)
            while data.count < AIActivitySocket.maximumBytes {
                let count = recv(fd, &buffer, min(buffer.count, AIActivitySocket.maximumBytes - data.count), 0)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
                if data.last == 10 { break }
            }
            if !data.isEmpty && data.count < AIActivitySocket.maximumBytes { onEvent(data) }
        }
    }

    deinit { stop() }
    enum SocketError: LocalizedError {
        case invalidDirectory, alreadyRunning, unavailable
        var errorDescription: String? {
            switch self {
            case .invalidDirectory: return "The private AI event socket is unavailable."
            case .alreadyRunning: return "Another Boring Notch instance is receiving AI events."
            case .unavailable: return "Could not start the AI event bridge."
            }
        }
    }
}

/// The existing helper executable doubles as a dependency-free, fail-open hook client.
enum AIActivityHookClient {
    static func run() {
        defer {
            // Codex Stop requires JSON rather than arbitrary stdout. Empty JSON is neutral.
            if CommandLine.arguments.contains("codex") { print("{}") }
        }
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--provider"), arguments.indices.contains(index + 1),
              let provider = AIProvider(rawValue: arguments[index + 1]),
              let input = readInput(),
              let json = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let event = normalize(json, provider: provider), event.isValid,
              var data = try? JSONEncoder().encode(event),
              data.count + 1 < AIActivitySocket.maximumBytes,
              let fd = AIActivitySocket.connect() else { return }
        defer { close(fd) }
        data.append(10)
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = send(fd, base.advanced(by: offset), bytes.count - offset, 0)
                guard count > 0 else { return }
                offset += count
            }
        }
    }

    private static func readInput() -> Data? {
        var data = Data()
        while let chunk = try? FileHandle.standardInput.read(upToCount: 65_536), !chunk.isEmpty {
            guard data.count + chunk.count <= 2_097_152 else { return nil }
            data.append(chunk)
        }
        return data.isEmpty ? nil : data
    }

    static func normalize(_ json: [String: Any], provider: AIProvider,
                          environment: [String: String] = ProcessInfo.processInfo.environment) -> AIActivityEvent? {
        guard let name = json["hook_event_name"] as? String,
              let sessionID = json["session_id"] as? String else { return nil }
        let tool = (json["tool_name"] as? String ?? "").lowercased()
        let toolID = json["tool_use_id"] as? String ?? json["item_id"] as? String ?? (tool.isEmpty ? nil : "tool:\(tool)")
        let isQuestion = ["askuserquestion", "request_user_input", "requestuserinput", "elicitation"].contains { tool.contains($0) }
        let isAsyncQuestion = isQuestion && tool.contains("async")
        var kind: AIActivityEventKind
        var reason: String?
        var action: (AIActivityAction, String?)?
        switch name {
        case "SessionStart": kind = .sessionStarted
        case "UserPromptSubmit": kind = .started
        case "PreToolUse":
            kind = isQuestion ? .attention : .activity
            if isQuestion { reason = "Waiting for your answer" }
            action = classify(tool: json["tool_name"] as? String ?? "", input: json["tool_input"] as? [String: Any] ?? [:])
        case "PermissionRequest": kind = .attention; reason = "Waiting for permission in the app"
        case "PostToolUse", "PostToolUseFailure", "PermissionDenied":
            // An asynchronous question returning only means it was presented, not answered.
            if name == "PostToolUse" && isAsyncQuestion { return nil }
            kind = .resolved
        case "Stop": kind = .stopped
        case "StopFailure": kind = .failed; reason = "The response failed; review it in the app"
        case "Interrupt": kind = .interrupted
        case "SessionEnd": kind = .sessionEnded
        case "SubagentStart": kind = .subagentStarted
        case "SubagentStop": kind = .subagentStopped
        case "Elicitation": kind = .attention; reason = "Waiting for your response to a connected tool"
        case "ElicitationResult": kind = .resolved
        case "Notification":
            // PermissionRequest and Elicitation carry request identity. Their delayed
            // notifications do not; replaying them creates an unresolvable yellow light.
            return nil
        default: return nil
        }
        var event = AIActivityEvent(provider: provider, sessionID: sessionID,
                                    runID: json["turn_id"] as? String, kind: kind)
        event.requestID = toolID
        // Claude Code's PermissionRequest carries no tool_use_id, so key it by tool. The tool's
        // result, failure or auto-mode denial then clears it along with its own request.
        let permissionID = tool.isEmpty ? nil : "permission:\(tool)"
        if name == "PermissionRequest" && json["tool_use_id"] == nil && json["item_id"] == nil {
            event.requestID = permissionID
        }
        if kind == .resolved && name != "ElicitationResult" { event.alsoResolves = permissionID }
        if name == "Elicitation" || name == "ElicitationResult" {
            event.requestID = "elicitation:" + (json["elicitation_id"] as? String ?? json["mcp_server_name"] as? String ?? "default")
        }
        event.agentID = json["agent_id"] as? String
        event.project = (json["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        event.hostSessionID = environment["CLAUDE_CODE_HOST_SESSION_ID"]
        event.hostBundleID = environment["__CFBundleIdentifier"].flatMap { id in
            id.count <= 128 && id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }) ? id : nil
        }
        // Only GUI-spawned hooks inherit the app's bundle identity. CLI sessions must not be
        // marked unavailable merely because the desktop app is not running.
        event.isDesktop = event.hostSessionID != nil
            || environment["__CFBundleIdentifier"] == provider.bundleIdentifier
        event.reason = reason
        event.action = action?.0
        event.actionDetail = action?.1
        if let background = json["background_tasks"] as? [[String: Any]] {
            event.hasBackgroundWork = background.contains { !["completed", "failed", "cancelled"].contains($0["status"] as? String ?? "running") }
        }
        return event
    }

    /// Maps a tool call to a caption. Only a file basename, program name, web host or agent
    /// type leaves this process; arguments, patterns, queries and contents never do.
    static func classify(tool: String, input: [String: Any]) -> (AIActivityAction, String?) {
        func label(_ value: String?) -> String? {
            guard let value else { return nil }
            let clean = String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(64))
            return clean.isEmpty ? nil : clean
        }
        func basename(_ keys: String...) -> String? {
            guard let path = keys.lazy.compactMap({ input[$0] as? String }).first(where: { !$0.isEmpty }) else { return nil }
            return label(URL(fileURLWithPath: path).lastPathComponent)
        }
        let name = tool.lowercased()
        switch name {
        case "read", "notebookread", "view":
            return (.reading, basename("file_path", "notebook_path", "path"))
        case "edit", "multiedit", "write", "notebookedit", "apply_patch", "str_replace_based_edit_tool":
            return (.editing, basename("file_path", "notebook_path", "path"))
        case "grep", "glob", "ls", "toolsearch":
            return (.searching, nil)
        case "bash", "shell", "local_shell", "exec_command", "unified_exec":
            let command = input["command"] as? String ?? (input["command"] as? [String])?.joined(separator: " ")
                ?? input["cmd"] as? String ?? ""
            return classify(command: command)
        case "webfetch":
            return (.browsing, label((input["url"] as? String).flatMap { URL(string: $0)?.host }))
        case "websearch", "web_search":
            return (.browsing, nil)
        case "task", "agent":
            return (.delegating, label(input["subagent_type"] as? String))
        case "todowrite", "update_plan", "exitplanmode":
            return (.thinking, nil)
        default:
            // mcp__<server>__<tool>: the server name says enough.
            let parts = tool.components(separatedBy: "__")
            return (.usingTool, parts.count >= 3 && parts[0] == "mcp" ? label(parts[1]) : nil)
        }
    }

    static func classify(command: String) -> (AIActivityAction, String?) {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        // Skip environment assignments and wrappers; they can carry secrets and say little.
        let program = tokens.first { !$0.contains("=") && !["sudo", "env", "time", "exec", "command"].contains($0) }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        let words = tokens.flatMap { $0.lowercased().split(separator: "/").map(String.init) }
        let testRunners: Set = ["pytest", "jest", "vitest", "rspec", "ctest", "xctest", "phpunit"]
        if words.contains(where: { $0 == "test" || $0 == "tests" || $0.hasPrefix("test:") || testRunners.contains($0)
            || ($0.hasSuffix("tests") && $0.count > 5) }) {
            return (.testing, nil)
        }
        let safe = program.flatMap { name -> String? in
            name.count <= 32 && name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._+-".contains($0)) }) ? name : nil
        }
        return (.running, safe)
    }
}
