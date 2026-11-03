import Foundation
import Darwin

/// Uses the installed Codex CLI; credentials and execution settings stay with Codex.
public struct CodexReplyTransport: Sendable {

    public let executableURL: URL
    public init(executableURL: URL) { self.executableURL = executableURL }

    public func send(sessionID: String, turnID: String?, text: String) async -> CodexReplyOutcome {
        await Task.detached {
            guard UUID(uuidString: sessionID) != nil,
                  let turnID = turnID, UUID(uuidString: turnID) != nil,
                  !text.contains("\0") else { return .unavailable }
            // Hooks can identify a shared session. Prove that the originating turn
            // belongs to this exact thread before placing anything in its queue.
            do {
                let rpc = try CodexReplyChild(executable: executableURL, arguments: ["app-server", "--stdio"])
                defer { rpc.close() }
                _ = try rpc.request(id: 1, method: "initialize", params: [
                    "clientInfo": ["name": "boring_notch_reply", "version": "1.0"]
                ])
                try rpc.write(["method": "initialized"])
                let result = try rpc.request(id: 2, method: "thread/read", params: [
                    "threadId": sessionID, "includeTurns": false
                ])
                guard let thread = result["thread"] as? [String: Any],
                      thread["id"] as? String == sessionID,
                      thread["sessionId"] as? String == sessionID,
                      thread["parentThreadId"] is NSNull else { return .unavailable }
                let turns = try rpc.request(id: 3, method: "thread/turns/list", params: [
                    "threadId": sessionID, "limit": 100,
                    "sortDirection": "desc", "itemsView": "notLoaded"
                ])
                guard let data = turns["data"] as? [[String: Any]],
                      data.contains(where: { $0["id"] as? String == turnID }) else { return .unavailable }
            } catch { return .unavailable }

            // Process arguments are passed directly, never interpreted by a shell.
            // queue currently accepts text only through --message. Never log argv.
            let child: CodexReplyChild
            do {
                child = try CodexReplyChild(executable: executableURL, arguments: [
                    "queue", "--thread", sessionID, "--message", text, "--resume"
                ], captureErrors: true)
            } catch { return .failed }
            defer { child.close() }
            do {
                let output = try child.readToEnd()
                guard child.exitStatus == 0 else {
                    // An abnormal exit could happen after the queue write.
                    return .uncertain
                }
                return Self.classifyQueueOutput(output)
            } catch { return .uncertain }
        }.value
    }

    public static func classifyQueueOutput(_ output: String) -> CodexReplyOutcome {
        guard output.contains("Queued message ") else { return .uncertain }
        return output.lowercased().contains("could not resume thread") ? .queuedNeedsOpen : .queued
    }
}

/// Bounded, short-lived CLI connection. It never logs response bodies or errors.
private final class CodexReplyChild {
    private var processID: pid_t = 0
    private var running = false
    private let lifetimeLock = NSLock()
    private var input: FileHandle?
    private var output: FileHandle?
    private(set) var exitStatus: Int32 = -1
    private var buffer = Data()
    private var receivedBytes = 0
    private var deadline: DispatchSourceTimer?
    private static let maximumOutputBytes = 1_048_576
    private enum Failure: Error { case closed, malformed, rejected, oversized }

    init(executable: URL, arguments: [String], captureErrors: Bool = false) throws {
        var inputFDs: [Int32] = [-1, -1]
        var outputFDs: [Int32] = [-1, -1]
        guard pipe(&inputFDs) == 0 else { throw Failure.closed }
        guard pipe(&outputFDs) == 0 else {
            inputFDs.forEach { Darwin.close($0) }
            throw Failure.closed
        }
        var spawned = false
        defer {
            Darwin.close(inputFDs[0])
            Darwin.close(outputFDs[1])
            if !spawned { Darwin.close(inputFDs[1]); Darwin.close(outputFDs[0]) }
        }
        for fd in inputFDs + outputFDs { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        // A server that exits before initialization must fail this send, not the app.
        _ = fcntl(inputFDs[1], F_SETNOSIGPIPE, 1)
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, inputFDs[0], STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, outputFDs[1], STDOUT_FILENO)
        if captureErrors {
            posix_spawn_file_actions_adddup2(&actions, outputFDs[1], STDERR_FILENO)
        } else {
            posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        }
        for fd in inputFDs + outputFDs { posix_spawn_file_actions_addclose(&actions, fd) }
        // Foundation Process uses filesystem strings for argv on macOS and
        // normalizes composed Unicode. Explicit UTF-8 C strings preserve input.
        let strings = ([executable.path] + arguments).map { $0.withCString { strdup($0)! } }
        defer { strings.forEach { free($0) } }
        var argv: [UnsafeMutablePointer<CChar>?] = strings.map { $0 } + [nil]
        let environment = ProcessInfo.processInfo.environment.map { key, value in
            "\(key)=\(value)".withCString { strdup($0)! }
        }
        defer { environment.forEach { free($0) } }
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { $0 } + [nil]
        let code = posix_spawn(&processID, executable.path, &actions, nil, &argv, &envp)
        guard code == 0 else { throw Failure.closed }
        spawned = true
        running = true
        input = FileHandle(fileDescriptor: inputFDs[1], closeOnDealloc: true)
        output = FileHandle(fileDescriptor: outputFDs[0], closeOnDealloc: true)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 20)
        timer.setEventHandler { [weak self] in self?.terminate() }
        timer.resume()
        deadline = timer
    }

    func write(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0a)
        try input?.write(contentsOf: data)
    }

    func request(id: Int, method: String, params: [String: Any]) throws -> [String: Any] {
        try write(["id": id, "method": method, "params": params])
        while true {
            while let newline = buffer.firstIndex(of: 0x0a) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw Failure.malformed
                }
                guard object["id"] as? Int == id else { continue }
                guard let result = object["result"] as? [String: Any] else { throw Failure.rejected }
                return result
            }
            buffer.append(try readChunk())
        }
    }

    func readToEnd() throws -> String {
        var data = Data()
        while true {
            let chunk = output?.availableData ?? Data()
            if chunk.isEmpty { break }
            receivedBytes += chunk.count
            guard receivedBytes <= Self.maximumOutputBytes else { throw Failure.oversized }
            data.append(chunk)
        }
        waitForExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func readChunk() throws -> Data {
        let data = output?.availableData ?? Data()
        guard !data.isEmpty else { throw Failure.closed }
        receivedBytes += data.count
        guard receivedBytes <= Self.maximumOutputBytes else { throw Failure.oversized }
        return data
    }

    private func terminate() {
        lifetimeLock.lock()
        defer { lifetimeLock.unlock() }
        if running { Darwin.kill(processID, SIGKILL) }
    }

    private func waitForExit() {
        while true {
            lifetimeLock.lock()
            guard running else { lifetimeLock.unlock(); return }
            var status: Int32 = 0
            let result = waitpid(processID, &status, WNOHANG)
            if result == processID || (result == -1 && errno != EINTR) {
                running = false
                exitStatus = status
                lifetimeLock.unlock()
                return
            }
            lifetimeLock.unlock()
            usleep(10_000)
        }
    }

    func close() {
        deadline?.cancel()
        terminate()
        try? input?.close()
        try? output?.close()
        waitForExit()
    }
}
