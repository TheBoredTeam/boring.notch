//
//  ClaudeApprovalBridge.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Darwin
import Defaults

struct ClaudeApprovalRequest: Identifiable {
    let id: UUID
    let toolName: String
    let detail: String
    let projectName: String
}

struct ClaudeQuestionOption: Identifiable, Sendable {
    let label: String
    let detail: String?

    var id: String { label }
}

struct ClaudeQuestion: Identifiable, Sendable {
    let text: String
    let header: String
    let options: [ClaudeQuestionOption]
    let multiSelect: Bool

    var id: String { text }
}

struct ClaudeQuestionRequest: Identifiable, Sendable {
    let id: UUID
    let projectName: String
    let questions: [ClaudeQuestion]
}

@MainActor
final class ClaudeApprovalBridge: ObservableObject {
    static let shared = ClaudeApprovalBridge()
    static let port: UInt16 = 37892
    static let hookURL = "http://127.0.0.1:37892/claude/permission"
    static let questionHookURL = "http://127.0.0.1:37892/claude/question"

    @Published private(set) var pending: [ClaudeApprovalRequest] = []
    @Published private(set) var pendingQuestions: [ClaudeQuestionRequest] = []
    @Published private(set) var errorMessage: String?

    private var listener: DispatchSourceRead?
    private var connections: [UUID: Int32] = [:]
    private var questionInputs: [UUID: [String: Any]] = [:]
    private var token: String?
    private let queue = DispatchQueue(label: "boringNotch.claudeApprovalBridge", qos: .utility)

    private init() {}

    func updateEnabled() {
        guard Defaults[.enableAISessionFeature], Defaults[.enableClaudeApprovalBridge] else {
            stop()
            return
        }
        guard listener == nil else { return }
        guard let configuredToken = Self.configuredToken() else {
            errorMessage = "Install the local approval hook before enabling this option."
            return
        }
        token = configuredToken

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            errorMessage = String(cString: strerror(errno))
            return
        }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = Self.port.bigEndian
        address.sin_addr = in_addr(s_addr: in_addr_t(0x7f000001).bigEndian)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 8) == 0 else {
            errorMessage = String(cString: strerror(errno))
            Darwin.close(fd)
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            let client = Darwin.accept(fd, nil, nil)
            guard client >= 0 else { return }
            Task { @MainActor [weak self] in
                if let self { self.receive(client) }
                else { Darwin.close(client) }
            }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        listener = source
        errorMessage = nil
    }

    func respond(to id: UUID, allow: Bool) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        pending.removeAll { $0.id == id }
        send(Self.permissionDecision(allow: allow), to: connection)
    }

    func answerQuestion(id: UUID, answers: [String: String]) {
        guard let request = pendingQuestions.first(where: { $0.id == id }),
              let input = questionInputs[id],
              request.questions.allSatisfy({ !(answers[$0.text] ?? "").isEmpty }),
              let connection = connections.removeValue(forKey: id) else { return }
        questionInputs.removeValue(forKey: id)
        pendingQuestions.removeAll { $0.id == id }
        send(Self.questionDecision(input: input, answers: answers), to: connection)
    }

    func answerInClaude(id: UUID) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        questionInputs.removeValue(forKey: id)
        pendingQuestions.removeAll { $0.id == id }
        send([:], to: connection)
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        token = nil
        for connection in connections.values { send([:], to: connection) }
        connections.removeAll()
        pending.removeAll()
        pendingQuestions.removeAll()
        questionInputs.removeAll()
    }

    private func receive(_ connection: Int32) {
        var noSignal: Int32 = 1
        setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let request = Self.readRequest(from: connection) else {
                Darwin.close(connection)
                return
            }
            Task { @MainActor [weak self] in
                if let self { self.handle(request, connection: connection) }
                else { Darwin.close(connection) }
            }
        }
    }

    private func handle(_ request: HTTPRequest, connection: Int32) {
        guard let token,
              request.authorization == "Bearer \(token)",
              let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            send([:], to: connection, status: "401 Unauthorized")
            return
        }

        if request.path == "/claude/question",
           body["hook_event_name"] as? String == "PreToolUse",
           body["tool_name"] as? String == "AskUserQuestion" {
            handleQuestion(body, connection: connection)
            return
        }
        guard request.path == "/claude/permission",
              body["hook_event_name"] as? String == "PermissionRequest" else {
            send([:], to: connection, status: "400 Bad Request")
            return
        }

        // Interactive tools must retain their native prompt unless their full input is supplied.
        if ["AskUserQuestion", "ExitPlanMode"].contains(body["tool_name"] as? String ?? "") {
            send([:], to: connection)
            return
        }

        let id = UUID()
        let toolName = body["tool_name"] as? String ?? "Tool"
        let input = body["tool_input"] as? [String: Any] ?? [:]
        let detail = (try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "No tool parameters provided"
        let cwd = body["cwd"] as? String
        let projectName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown project"
        pending.append(ClaudeApprovalRequest(
            id: id,
            toolName: toolName,
            detail: detail,
            projectName: projectName
        ))
        connections[id] = connection
        showApprovalTab()

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, let connection = self.connections.removeValue(forKey: id) else { return }
            self.pending.removeAll { $0.id == id }
            self.send([:], to: connection)
        }
    }

    private func handleQuestion(_ body: [String: Any], connection: Int32) {
        guard let input = body["tool_input"] as? [String: Any],
              let questions = Self.parseQuestions(input) else {
            send([:], to: connection)
            return
        }
        let id = UUID()
        let projectName = (body["cwd"] as? String)
            .map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown project"
        pendingQuestions.append(ClaudeQuestionRequest(
            id: id,
            projectName: projectName,
            questions: questions
        ))
        questionInputs[id] = input
        connections[id] = connection
        showApprovalTab()

        DispatchQueue.main.asyncAfter(deadline: .now() + 290) { [weak self] in
            guard let self, let connection = self.connections.removeValue(forKey: id) else { return }
            self.pendingQuestions.removeAll { $0.id == id }
            self.questionInputs.removeValue(forKey: id)
            self.send([:], to: connection)
        }
    }

    private func showApprovalTab() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let location = NSEvent.mouseLocation
        let model = NSScreen.screens
            .first(where: { $0.frame.contains(location) })?
            .displayUUID
            .flatMap { appDelegate.viewModels[$0] } ?? appDelegate.vm
        BoringViewCoordinator.shared.currentView = .aiSessions
        if model.notchState == .closed { _ = model.open() }
    }

    private func send(_ object: [String: Any], to connection: Int32, status: String = "200 OK") {
        guard let body = try? JSONSerialization.data(withJSONObject: object) else {
            Darwin.close(connection)
            return
        }
        let header = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        let response = Data(header.utf8) + body
        response.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.send(connection, base.advanced(by: sent), bytes.count - sent, 0)
                guard count > 0 else { break }
                sent += count
            }
        }
        Darwin.close(connection)
    }

    nonisolated static func permissionDecision(allow: Bool) -> [String: Any] {
        [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": allow ? "allow" : "deny"],
            ],
        ]
    }

    nonisolated static func parseQuestions(_ input: [String: Any]) -> [ClaudeQuestion]? {
        guard let rawQuestions = input["questions"] as? [[String: Any]],
              (1...4).contains(rawQuestions.count) else { return nil }
        var questions: [ClaudeQuestion] = []
        for raw in rawQuestions {
            guard let text = raw["question"] as? String, !text.isEmpty,
                  let rawOptions = raw["options"] as? [[String: Any]],
                  !rawOptions.isEmpty else { return nil }
            let options = rawOptions.compactMap { option -> ClaudeQuestionOption? in
                guard let label = option["label"] as? String, !label.isEmpty else { return nil }
                return ClaudeQuestionOption(label: label, detail: option["description"] as? String)
            }
            guard options.count == rawOptions.count,
                  Set(options.map(\.label)).count == options.count else { return nil }
            questions.append(ClaudeQuestion(
                text: text,
                header: raw["header"] as? String ?? "Question",
                options: options,
                multiSelect: raw["multiSelect"] as? Bool ?? false
            ))
        }
        guard Set(questions.map(\.text)).count == questions.count else { return nil }
        return questions
    }

    nonisolated static func questionDecision(
        input: [String: Any],
        answers: [String: String]
    ) -> [String: Any] {
        var updatedInput = input
        updatedInput["answers"] = answers
        return [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": updatedInput,
            ],
        ]
    }

    private static func configuredToken() -> String? {
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settings),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = object["hooks"] as? [String: Any],
              let requests = hooks["PermissionRequest"] as? [[String: Any]] else { return nil }
        for group in requests {
            guard let entries = group["hooks"] as? [[String: Any]] else { continue }
            for entry in entries where entry["url"] as? String == hookURL {
                guard let headers = entry["headers"] as? [String: String],
                      let authorization = headers["Authorization"],
                      authorization.hasPrefix("Bearer ") else { continue }
                return String(authorization.dropFirst("Bearer ".count))
            }
        }
        return nil
    }

    struct HTTPRequest: Sendable {
        let path: String
        let authorization: String?
        let body: Data
    }

    private nonisolated static func readRequest(from connection: Int32) -> HTTPRequest? {
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while received.count <= 128 * 1024 {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.recv(connection, bytes.baseAddress, bytes.count, 0)
            }
            guard count > 0 else { return nil }
            received.append(contentsOf: buffer.prefix(count))
            if let request = parseRequest(received) { return request }
        }
        return nil
    }

    nonisolated static func parseRequest(_ data: Data) -> HTTPRequest? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: delimiter),
              let header = String(data: data[..<range.lowerBound], encoding: .utf8) else { return nil }
        let lines = header.components(separatedBy: "\r\n")
        guard let first = lines.first, first.hasPrefix("POST "),
              let path = first.split(separator: " ").dropFirst().first.map(String.init) else { return nil }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separator]).lowercased()
            fields[name] = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
        }
        guard let size = fields["content-length"].flatMap(Int.init), size >= 0, size <= 64 * 1024 else {
            return nil
        }
        let bodyStart = range.upperBound
        guard data.count - bodyStart >= size else { return nil }
        return HTTPRequest(
            path: path,
            authorization: fields["authorization"],
            body: data[bodyStart..<(bodyStart + size)]
        )
    }
}
