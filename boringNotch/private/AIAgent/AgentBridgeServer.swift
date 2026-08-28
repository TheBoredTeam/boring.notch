//
//  AgentBridgeServer.swift
//  boringNotch
//
//  HTTP localhost bridge the Claude Code hook scripts talk to.
//  boring-decide.sh POSTs the raw PreToolUse hook payload; for tools the
//  user should decide on, the response is held open until the user answers
//  from the notch (or the hold times out and we fall through to Claude
//  Code's normal permission flow). Event-only hooks (SessionStart, Stop,
//  Notification, …) are fire-and-forget.
//
//  Why TCP/HTTP: the app talks to external processes; localhost TCP works
//  across that boundary and is covered by the network.server /
//  network.client entitlements. The app scans a small fixed port range for
//  a free port; the hook scripts scan the same range to discover it. HTTP
//  (instead of raw TCP lines) lets the hooks be plain `curl` one-liners.
//
//  Endpoints:
//    GET  /v1/health   → {"ok":true}
//    GET  /v1/state    → debug snapshot (sessions, pending cards)
//    POST /v1/hook     → raw Claude Code hook payload
//    POST /v1/respond  → {requestID, decision: allow|deny|answer, reason?, answers?}
//

import Foundation
import Defaults
import os.log

private let agentBridgeLog = OSLog(subsystem: "com.boringnotch.agent", category: "bridge")

private func blog(_ msg: String) {
    os_log("%{public}@", log: agentBridgeLog, type: .info, msg)
}

// MARK: - Delegate (main actor)

@MainActor
protocol AgentBridgeDelegate: AnyObject {
    func bridge(didRegisterInstance info: AgentInstanceInfo)
    func bridge(didReceiveEvent event: AgentEvent, sessionID: String)
    func bridge(didReceivePermission permission: AgentPendingPermission)
    func bridge(didReceiveQuestion question: AgentPendingQuestion)
    /// A held request timed out without an answer — drop the card.
    func bridgeDidExpire(requestID: String)
    /// Debug snapshot for GET /v1/state.
    func bridgeStateSnapshot() -> AgentJSON
}

// MARK: - Server

final class AgentBridgeServer: @unchecked Sendable {
    /// Scan this small range for a free localhost port. Keep in sync with
    /// the PORT_RANGE in the hook scripts.
    static let portBase = 8742
    static let portRange: [Int] = Array(portBase..<(portBase + 11))
    static let bridgeHost = "127.0.0.1"

    /// How long a PreToolUse decision may sit unanswered before we fall
    /// through to Claude Code's normal permission flow.
    static let holdTimeout: TimeInterval = 30

    private weak var delegate: (any AgentBridgeDelegate)?
    private var listenFD: Int32 = -1
    private var running = false
    private let workQueue = DispatchQueue(label: "boringnotch.agent-bridge", attributes: .concurrent)

    // Sessions the notch itself spawned (managed `claude -p` runs). Only
    // their tool requests hold for a notch decision; external terminal
    // sessions pass through instantly so Claude Code's own permission flow
    // is never delayed.
    private let managedLock = NSLock()
    private var managedSessions: Set<String> = []

    // Held PreToolUse requests awaiting a user decision.
    private let heldLock = NSLock()
    private var heldRequests: [String: HeldRequest] = [:]
    // Tools the user approved with "Always", per session — no card next time.
    private var alwaysAllowedTools: [String: Set<String>] = [:]

    final class HeldRequest {
        let id: String
        let sessionID: String
        private let lock = NSLock()
        private var resumed = false
        private var body: String?

        init(id: String, sessionID: String) {
            self.id = id
            self.sessionID = sessionID
        }

        /// Resumes exactly once with the response body for the hook.
        func fulfill(_ responseBody: String) -> Bool {
            lock.lock()
            if resumed {
                lock.unlock()
                return false
            }
            resumed = true
            body = responseBody
            lock.unlock()
            return true
        }

        var response: String? {
            lock.lock()
            defer { lock.unlock() }
            return body
        }
    }

    func start(delegate: any AgentBridgeDelegate) -> Bool {
        self.delegate = delegate
        stop()

        var boundFD: Int32 = -1
        var chosenPort = 0
        for port in Self.portRange {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else {
                blog("socket() failed: errno \(errno)")
                return false
            }

            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(port).bigEndian
            addr.sin_addr.s_addr = inet_addr(Self.bridgeHost)

            let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    bind(fd, sa, socklen_t(MemoryLayout<sockaddr>.size))
                }
            }
            if bindResult != 0 {
                close(fd)
                continue
            }
            if listen(fd, 32) != 0 {
                close(fd)
                continue
            }

            boundFD = fd
            chosenPort = port
            break
        }

        guard boundFD >= 0 else {
            blog("could not bind any bridge port in range \(Self.portBase)-\(Self.portBase + Self.portRange.count - 1)")
            return false
        }

        listenFD = boundFD
        running = true
        blog("bridge listening on \(Self.bridgeHost):\(chosenPort)")
        Thread.detachNewThread { [weak self] in
            self?.acceptLoop()
        }
        return true
    }

    func stop() {
        running = false
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        heldLock.lock()
        let all = Array(heldRequests.values)
        heldRequests.removeAll()
        heldLock.unlock()
        // Fail open: anything still held falls through.
        for held in all { _ = held.fulfill("") }
        blog("bridge stopped")
    }

    // MARK: Accept + request reading

    private func acceptLoop() {
        while running {
            var clientAddr = sockaddr()
            var len = socklen_t(MemoryLayout<sockaddr>.size)
            let client = accept(listenFD, &clientAddr, &len)
            if client < 0 {
                if running { usleep(50_000) }
                continue
            }
            configureSocket(client)
            workQueue.async { [weak self] in
                self?.handleConnection(client)
            }
        }
    }

    private func configureSocket(_ fd: Int32) {
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        // Long enough to cover the hold timeout with margin.
        var timeout = timeval(tv_sec: 300, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private func handleConnection(_ fd: Int32) {
        defer { close(fd) }

        var buffer = Data()
        var scratch = [UInt8](repeating: 0, count: 65_536)
        let headerEndMarker = Data("\r\n\r\n".utf8)

        while running {
            let n = read(fd, &scratch, scratch.count)
            if n <= 0 { return }
            buffer.append(contentsOf: scratch[0..<n])

            guard let headerRange = buffer.range(of: headerEndMarker) else {
                if buffer.count > 1_048_576 { return } // absurd header, drop
                continue
            }

            // Header block (request line + headers).
            let headerData = buffer.subdata(in: buffer.startIndex..<headerRange.lowerBound)
            guard let headerText = String(data: headerData, encoding: .utf8),
                  let request = parseRequestHead(headerText) else {
                _ = tryWrite(fd, response(status: "400 Bad Request", body: "{\"error\":\"bad request\"}"))
                return
            }

            // Body bytes: whatever already arrived after the marker, then
            // keep reading until Content-Length is satisfied.
            var body = buffer.subdata(in: headerRange.upperBound..<buffer.endIndex)
            while body.count < request.contentLength {
                let r = read(fd, &scratch, scratch.count)
                if r <= 0 { break }
                body.append(contentsOf: scratch[0..<r])
            }
            if body.count > request.contentLength {
                body = body.prefix(request.contentLength)
            }

            let responseBody = route(request: request, body: Data(body))
            _ = tryWrite(fd, responseBody)
            return // Connection: close — one request per connection
        }
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let contentLength: Int
    }

    private func parseRequestHead(_ text: String) -> HTTPRequest? {
        var lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0]).uppercased()
        let path = String(parts[1])
        var contentLength = 0
        for line in lines {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            if pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(pair[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return HTTPRequest(method: method, path: path, contentLength: max(0, contentLength))
    }

    private func decodeBody(_ body: Data) -> AgentJSON? {
        guard !body.isEmpty else { return .object([:]) }
        return try? JSONDecoder().decode(AgentJSON.self, from: body)
    }

    // MARK: Routing

    private func route(request: HTTPRequest, body: Data) -> String {
        switch (request.method, request.path) {
        case ("GET", "/v1/health"):
            return response(status: "200 OK", body: "{\"ok\":true,\"agent\":\"claude-code\"}")
        case ("GET", "/v1/state"):
            return stateResponse()
        case ("POST", "/v1/hook"):
            guard let payload = decodeBody(body) else {
                return response(status: "400 Bad Request", body: "{\"error\":\"invalid json\"}")
            }
            return handleHook(payload)
        case ("POST", "/v1/respond"):
            guard let payload = decodeBody(body) else {
                return response(status: "400 Bad Request", body: "{\"error\":\"invalid json\"}")
            }
            handleRespond(payload)
            return response(status: "200 OK", body: "{\"ok\":true}")
        default:
            return response(status: "404 Not Found", body: "{}")
        }
    }

    private func stateResponse() -> String {
        let box = SnapshotBox()
        let sem = DispatchSemaphore(value: 0)
        Task { @MainActor [weak self] in
            box.value = self?.delegate?.bridgeStateSnapshot() ?? .null
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 3)
        guard let data = try? JSONEncoder().encode(box.value) else {
            return response(status: "500 Internal Server Error", body: "{}")
        }
        return response(status: "200 OK", body: String(data: data, encoding: .utf8) ?? "{}")
    }

    private final class SnapshotBox: @unchecked Sendable {
        var value: AgentJSON = .null
    }

    // MARK: Hook dispatch

    /// Handles a raw Claude Code hook payload. Returns the full HTTP response
    /// (hookSpecificOutput JSON or empty body for fall-through).
    private func handleHook(_ payload: AgentJSON) -> String {
        guard let eventName = payload["hook_event_name"]?.string else {
            return response(status: "400 Bad Request", body: "{}")
        }
        let sessionID = payload["session_id"]?.string ?? "unknown"
        let directory = payload["cwd"]?.string
        let transcriptPath = payload["transcript_path"]?.string

        switch eventName {
        case "SessionStart":
            notifyMain(.sessionStarted(sessionID: sessionID, directory: directory))
            registerInstance(sessionID: sessionID, directory: directory)
            return response(status: "200 OK", body: "")

        case "UserPromptSubmit":
            let text = payload["prompt"]?.string ?? ""
            notifyMain(.promptSubmitted(sessionID: sessionID, text: text))
            return response(status: "200 OK", body: "")

        case "PreToolUse":
            return handlePreToolUse(payload, sessionID: sessionID, directory: directory)

        case "Stop":
            let reply = transcriptPath.flatMap { Self.lastAssistantReply(from: $0) }
            notifyMain(.stopped(sessionID: sessionID, reply: reply))
            return response(status: "200 OK", body: "")

        case "SessionEnd":
            notifyMain(.sessionEnded(sessionID: sessionID))
            return response(status: "200 OK", body: "")

        case "Notification":
            let message = payload["message"]?.string ?? "Claude needs your attention"
            notifyMain(.attention(sessionID: sessionID, message: message))
            return response(status: "200 OK", body: "")

        default:
            return response(status: "200 OK", body: "")
        }
    }

    private func handlePreToolUse(_ payload: AgentJSON, sessionID: String, directory: String?) -> String {
        let tool = payload["tool_name"]?.string ?? ""
        let input = payload["tool_input"]
        let detail = Self.describe(tool: tool, input: input)

        // Every tool use is surfaced as activity.
        notifyMain(.toolUsed(sessionID: sessionID, tool: tool, detail: detail))

        // Only notch-driven sessions (or, when opted in, every session) hold
        // for a decision here. External terminal sessions return immediately
        // so their normal permission flow never waits on the notch.
        guard isManaged(sessionID) || Defaults[.aiAgentHoldExternalTools] else {
            return response(status: "200 OK", body: "")
        }

        // "Always allow" from an earlier card skips the hold for this tool.
        heldLock.lock()
        let autoAllowed = alwaysAllowedTools[sessionID]?.contains(tool) ?? false
        heldLock.unlock()
        if autoAllowed {
            return response(status: "200 OK", body: Self.hookOutput(
                permissionDecision: "allow",
                reason: "Auto-approved (Always allow set in Boring Notch)"))
        }

        // AskUserQuestion → held question card with option buttons.
        if tool == "AskUserQuestion" {
            let questions = (input?["questions"]?.array ?? []).compactMap(AgentQuestionItem.parse)
            guard !questions.isEmpty else { return response(status: "200 OK", body: "") }

            let requestID = "q-" + UUID().uuidString.prefix(8)
            let held = HeldRequest(id: requestID, sessionID: sessionID)
            heldLock.lock()
            heldRequests[requestID] = held
            heldLock.unlock()

            let question = AgentPendingQuestion(
                id: requestID,
                sessionID: sessionID,
                questions: questions,
                directory: directory,
                arrivedAt: Date())
            Task { @MainActor [weak delegate] in
                delegate?.bridge(didReceiveQuestion: question)
            }
            blog("held question \(requestID) (session \(sessionID.prefix(8)))")
            let heldBody = waitOn(held) ?? ""
            return response(status: "200 OK", body: heldBody)
        }

        // Mutating tools → held permission card. Read-only tools pass
        // straight through so cards never become noise.
        guard Self.isDecisionTool(tool) else {
            return response(status: "200 OK", body: "")
        }

        let requestID = "p-" + UUID().uuidString.prefix(8)
        let held = HeldRequest(id: requestID, sessionID: sessionID)
        heldLock.lock()
        heldRequests[requestID] = held
        heldLock.unlock()

        let permission = AgentPendingPermission(
            id: requestID,
            sessionID: sessionID,
            tool: tool,
            title: Self.title(for: tool),
            detail: detail,
            input: input,
            directory: directory,
            arrivedAt: Date())
        Task { @MainActor [weak delegate] in
            delegate?.bridge(didReceivePermission: permission)
        }
        blog("held permission \(requestID) (\(tool)) for session \(sessionID.prefix(8))")
        let heldBody = waitOn(held) ?? ""
        return response(status: "200 OK", body: heldBody)
    }

    // MARK: User responses

    /// Marks a session as notch-driven so its tool requests hold for a
    /// decision from the notch.
    func markManaged(sessionID: String) {
        managedLock.lock()
        managedSessions.insert(sessionID)
        managedLock.unlock()
    }

    func clearManaged(sessionID: String) {
        managedLock.lock()
        managedSessions.remove(sessionID)
        managedLock.unlock()
    }

    private func isManaged(_ sessionID: String) -> Bool {
        managedLock.lock()
        defer { managedLock.unlock() }
        return managedSessions.contains(sessionID)
    }

    /// In-process answer path used by the view model (cards in the notch).
    func respond(requestID: String, decision: AgentDecision) {
        var payload: [String: AgentJSON] = ["requestID": .string(requestID)]
        switch decision {
        case .allow:
            payload["decision"] = .string("allow")
        case .deny(let reason):
            payload["decision"] = .string("deny")
            if let reason { payload["reason"] = .string(reason) }
        case .answers(let answers):
            payload["decision"] = .string("answer")
            payload["answers"] = .array(answers.map { .array($0.map(AgentJSON.string)) })
        }
        handleRespond(.object(payload))
    }

    /// Marks a tool as always-allowed within a session (the "Always" button).
    func allowAlways(sessionID: String, tool: String) {
        heldLock.lock()
        alwaysAllowedTools[sessionID, default: []].insert(tool)
        heldLock.unlock()
    }

    private func handleRespond(_ payload: AgentJSON) {
        guard let requestID = payload["requestID"]?.string else { return }
        heldLock.lock()
        let held = heldRequests.removeValue(forKey: requestID)
        heldLock.unlock()
        guard let held else { return }

        let decision = payload["decision"]?.string ?? "deny"
        let body: String
        switch decision {
        case "allow":
            body = Self.hookOutput(permissionDecision: "allow", reason: "Approved from Boring Notch")
        case "answer":
            let answers = (payload["answers"]?.array ?? [])
                .map { $0.array?.compactMap(\.string) ?? [] }
            body = Self.hookOutput(permissionDecision: "deny", reason: Self.answerReason(answers: answers))
        default:
            let reason = payload["reason"]?.string ?? "Denied from Boring Notch"
            body = Self.hookOutput(permissionDecision: "deny", reason: reason)
        }

        if held.fulfill(body) {
            blog("responded \(decision) to \(requestID)")
        }
    }

    /// Called when a card is dismissed without a decision — we fall through
    /// so Claude Code's normal permission flow still applies.
    func fallThrough(requestID: String) {
        heldLock.lock()
        let held = heldRequests.removeValue(forKey: requestID)
        heldLock.unlock()
        _ = held?.fulfill("")
    }

    // MARK: Helpers

    private func registerInstance(sessionID: String, directory: String?) {
        let info = AgentInstanceInfo(
            id: sessionID,
            directory: directory ?? "~",
            pid: nil,
            managed: false,
            lastSeen: Date())
        Task { @MainActor [weak delegate] in
            delegate?.bridge(didRegisterInstance: info)
        }
    }

    private func notifyMain(_ event: AgentEvent) {
        let sessionID: String
        switch event {
        case .sessionStarted(let s, _), .sessionEnded(let s), .promptSubmitted(let s, _),
             .toolUsed(let s, _, _), .stopped(let s, _), .attention(let s, _), .errored(let s, _):
            sessionID = s
        }
        Task { @MainActor [weak delegate] in
            delegate?.bridge(didReceiveEvent: event, sessionID: sessionID)
        }
    }

    /// Blocks this connection's worker until the held request is fulfilled or
    /// times out. Returns the response body ("" = fall through).
    private func waitOn(_ held: HeldRequest) -> String? {
        let deadline = Date().addingTimeInterval(Self.holdTimeout)
        while Date() < deadline {
            if let body = held.response { return body }
            usleep(200_000)
        }
        // Expire: remove and tell the delegate to drop the card.
        heldLock.lock()
        heldRequests.removeValue(forKey: held.id)
        heldLock.unlock()
        held.fulfill("")
        Task { @MainActor [weak delegate] in
            delegate?.bridgeDidExpire(requestID: held.id)
        }
        return ""
    }

    private func tryWrite(_ fd: Int32, _ data: String) -> Bool {
        guard let payload = data.data(using: .utf8) else { return false }
        return payload.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var sent = 0
            let total = payload.count
            while sent < total {
                let n = write(fd, base + sent, total - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    private func response(status: String, body: String) -> String {
        let bodyBytes = body.data(using: .utf8)?.count ?? 0
        return "HTTP/1.1 \(status)\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(bodyBytes)\r\n" +
            "Connection: close\r\n" +
            "\r\n" + body
    }

    // MARK: Hook output + tool classification

    /// Builds the PreToolUse hookSpecificOutput JSON Claude Code expects.
    static func hookOutput(permissionDecision decision: String, reason: String) -> String {
        let escaped = jsonEscaped(reason)
        return "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\"," +
            "\"permissionDecision\":\"\(decision)\",\"permissionDecisionReason\":\"\(escaped)\"}}"
    }

    /// ASCII-safe JSON string escaping for shell transport.
    static func jsonEscaped(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else if scalar.value > 0x7E {
                    for unit in String(scalar).utf16 {
                        out += String(format: "\\u%04x", unit)
                    }
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    /// Tools the user should decide on from the notch. Read-only tools pass
    /// straight through so the card never becomes noise.
    static let decisionTools: Set<String> = [
        "Bash", "Write", "Edit", "MultiEdit", "NotebookEdit",
        "WebFetch", "WebSearch", "Task", "Agent",
    ]

    static func isDecisionTool(_ tool: String) -> Bool {
        decisionTools.contains(tool)
    }

    static func title(for tool: String) -> String {
        switch tool {
        case "Bash": return "Bash command"
        case "Write": return "Write file"
        case "Edit", "MultiEdit": return "Edit file"
        case "NotebookEdit": return "Edit notebook"
        case "WebFetch": return "Fetch URL"
        case "WebSearch": return "Web search"
        case "Task", "Agent": return "Launch subagent"
        default: return tool
        }
    }

    /// Short human detail for a tool input (command line / file path / URL).
    static func describe(tool: String, input: AgentJSON?) -> String {
        guard let input else { return "" }
        if let cmd = input["command"]?.string, !cmd.isEmpty { return cmd }
        if let file = input["file_path"]?.string, !file.isEmpty { return file }
        if let url = input["url"]?.string, !url.isEmpty { return url }
        if let query = input["query"]?.string, !query.isEmpty { return query }
        if let prompt = input["prompt"]?.string, !prompt.isEmpty { return prompt }
        return ""
    }

    /// Human-readable reason carrying the user's AskUserQuestion answers.
    static func answerReason(answers: [[String]]) -> String {
        var parts: [String] = []
        for (i, answer) in answers.enumerated() where !answer.isEmpty {
            let joined = answer.joined(separator: ", ")
            parts.append("Q\(i + 1): \(joined)")
        }
        let body = parts.isEmpty ? "answered" : parts.joined(separator: "; ")
        return "The user answered via Boring Notch: \(body). " +
            "Treat this as the user's answer and proceed with it. Do not ask again."
    }

    /// Best-effort last assistant reply from a session transcript, for the
    /// Stop-hook done card. Reads only the tail of the transcript.
    static func lastAssistantReply(from transcriptPath: String) -> String? {
        let url = URL(fileURLWithPath: transcriptPath)
        let stat = TranscriptStore.fileStat(url)
        guard let (_, tail) = TranscriptStore.readHeadAndTail(url: url, size: stat.size) else {
            return nil
        }
        var reply: String?
        for line in tail.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains("\"type\":\"assistant\""),
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONDecoder().decode(AgentJSON.self, from: lineData),
                  let content = obj["message"]?["content"]?.array else { continue }
            let textBlocks = content.filter { $0["type"]?.string == "text" }
                .compactMap { $0["text"]?.string }
                .joined(separator: "\n\n")
            if !textBlocks.isEmpty {
                reply = textBlocks
                break
            }
        }
        return reply.map { String($0.prefix(600)) }
    }
}