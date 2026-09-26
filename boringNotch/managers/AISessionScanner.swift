//
//  AISessionScanner.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

enum AISessionSource: String, Sendable {
    case codex = "Codex"
    case claude = "Claude Code"
    case openClaw = "OpenClaw"
}

enum AISessionStatus: String, Sendable {
    case working = "Working"
    case idle = "Idle"
}

struct AISessionRecord: Identifiable, Sendable {
    let id: String
    let source: AISessionSource
    let projectName: String
    let status: AISessionStatus
    let lastActivity: Date
    let latestMessage: String?
    let isDesktopSession: Bool
}

enum AISessionScanner {
    static func scan(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AISessionRecord] {
        let roots: [(URL, AISessionSource)] = [
            (homeDirectory.appendingPathComponent(".codex/sessions"), .codex),
            (homeDirectory.appendingPathComponent(".claude/projects"), .claude),
        ]
        let sessions = roots.flatMap { root, source in
            recentSessionFiles(in: root).compactMap { url, modifiedAt in
                let lines = readSessionLines(at: url)
                switch source {
                case .codex:
                    return parseCodex(lines: lines, file: url, modifiedAt: modifiedAt)
                case .claude:
                    return parseClaude(lines: lines, file: url, modifiedAt: modifiedAt)
                case .openClaw:
                    return nil
                }
            }
        }
        let openClawRoot = homeDirectory.appendingPathComponent(".openclaw/agents")
        let openClawSessions = recentSessionFiles(in: openClawRoot) { url in
            url.deletingLastPathComponent().lastPathComponent == "sessions"
        }.compactMap { url, modifiedAt in
            parseOpenClaw(lines: readSessionLines(at: url), file: url, modifiedAt: modifiedAt)
        }
        return (sessions + openClawSessions).sorted { $0.lastActivity > $1.lastActivity }
    }

    static func parseCodex(lines: [String], file: URL, modifiedAt: Date) -> AISessionRecord? {
        var sessionID: String?
        var cwd: String?
        var isDesktopSession = false
        var latestMessage: String?
        var latestTask: String?

        for line in lines {
            guard let value = object(from: line), let payload = value["payload"] as? [String: Any] else { continue }
            switch value["type"] as? String {
            case "session_meta":
                sessionID = payload["id"] as? String ?? sessionID
                cwd = payload["cwd"] as? String ?? cwd
                isDesktopSession = (payload["originator"] as? String) == "Codex Desktop"
            case "turn_context":
                cwd = payload["cwd"] as? String ?? cwd
            case "event_msg":
                if let event = payload["type"] as? String,
                   ["task_started", "task_complete", "turn_aborted"].contains(event) {
                    latestTask = event
                }
                if let message = payload["last_agent_message"] as? String, !message.isEmpty {
                    latestMessage = preview(message)
                }
            case "response_item":
                if payload["role"] as? String == "assistant",
                   let message = messageText(payload["content"]), !message.isEmpty {
                    latestMessage = preview(message)
                }
            default:
                break
            }
        }

        guard let sessionID, !sessionID.isEmpty else { return nil }
        let isRecent = Date().timeIntervalSince(modifiedAt) < 300
        return AISessionRecord(
            id: "codex:\(sessionID)",
            source: .codex,
            projectName: cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown project",
            status: isRecent && (latestTask == "task_started" || latestTask == nil) ? .working : .idle,
            lastActivity: modifiedAt,
            latestMessage: latestMessage,
            isDesktopSession: isDesktopSession
        )
    }

    static func parseClaude(lines: [String], file: URL, modifiedAt: Date) -> AISessionRecord? {
        var sessionID = file.deletingPathExtension().lastPathComponent
        var cwd: String?
        var latestMessage: String?
        var latestEvent: String?

        for line in lines {
            guard let value = object(from: line) else { continue }
            sessionID = value["sessionId"] as? String ?? sessionID
            cwd = value["cwd"] as? String ?? cwd
            guard let type = value["type"] as? String else { continue }
            if type == "user", let message = value["message"] as? [String: Any] {
                let content = message["content"]
                latestEvent = hasToolResult(content) ? "tool_result" : "user"
            } else if type == "assistant", let message = value["message"] as? [String: Any] {
                if let text = messageText(message["content"]), !text.isEmpty {
                    latestMessage = preview(text)
                    latestEvent = "assistant"
                }
                if hasToolUse(message["content"]) { latestEvent = "tool_use" }
            }
        }

        guard !sessionID.isEmpty else { return nil }
        let isRecent = Date().timeIntervalSince(modifiedAt) < 300
        return AISessionRecord(
            id: "claude:\(sessionID)",
            source: .claude,
            projectName: cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? file.deletingLastPathComponent().lastPathComponent,
            status: isRecent && ["user", "tool_result", "tool_use"].contains(latestEvent) ? .working : .idle,
            lastActivity: modifiedAt,
            latestMessage: latestMessage,
            isDesktopSession: false
        )
    }

    static func parseOpenClaw(lines: [String], file: URL, modifiedAt: Date) -> AISessionRecord? {
        var sessionID: String?
        var cwd: String?
        var latestMessage: String?
        var latestEvent: String?

        for line in lines {
            guard let value = object(from: line), let type = value["type"] as? String else { continue }
            if type == "session" {
                sessionID = value["id"] as? String ?? sessionID
                cwd = value["cwd"] as? String ?? cwd
            } else if type == "message", let message = value["message"] as? [String: Any],
                      let role = message["role"] as? String {
                if role == "assistant" {
                    if let text = messageText(message["content"]), !text.isEmpty {
                        latestMessage = preview(text)
                    }
                    latestEvent = hasOpenClawToolCall(message["content"]) ? "tool_call" : "assistant"
                } else if role == "user" || role == "toolResult" {
                    latestEvent = role
                }
            }
        }

        guard let sessionID, !sessionID.isEmpty else { return nil }
        let isRecent = Date().timeIntervalSince(modifiedAt) < 300
        return AISessionRecord(
            id: "openclaw:\(sessionID)",
            source: .openClaw,
            projectName: cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? file.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent,
            status: isRecent && ["user", "toolResult", "tool_call"].contains(latestEvent) ? .working : .idle,
            lastActivity: modifiedAt,
            latestMessage: latestMessage,
            isDesktopSession: false
        )
    }

    private static func recentSessionFiles(
        in root: URL, matching: (URL) -> Bool = { _ in true }
    ) -> [(URL, Date)] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" && matching(url) {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  let date = values.contentModificationDate else { continue }
            files.append((url, date))
        }
        return Array(files.sorted { $0.1 > $1.1 }.prefix(16))
    }

    private static func readSessionLines(at url: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let length = try? handle.seekToEnd() else { return [] }
        return readSessionLines(length: length) { offset, count in
            guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
            return try? handle.read(upToCount: count)
        }
    }

    static func readSessionLines(
        length: UInt64, read: (UInt64, Int) -> Data?
    ) -> [String] {
        let tailByteCount = 64 * 1024
        if length <= tailByteCount {
            guard let data = read(0, Int(length)) else { return [] }
            return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        }

        // Session metadata can be much longer than a small read buffer.
        let headerByteCount = 256 * 1024
        let head = read(0, min(Int(length), headerByteCount)) ?? Data()
        let firstLine = head.firstIndex(of: 0x0A).map { newline in
            String(decoding: head[..<newline], as: UTF8.self)
        }

        let tailOffset = length - UInt64(tailByteCount)
        guard let tail = read(tailOffset, tailByteCount),
              let firstNewline = tail.firstIndex(of: 0x0A) else {
            return firstLine.map { [$0] } ?? []
        }
        let tailLines = String(decoding: tail[tail.index(after: firstNewline)...], as: UTF8.self)
            .split(separator: "\n").map(String.init)
        return (firstLine.map { [$0] } ?? []) + tailLines
    }

    private static func object(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func messageText(_ content: Any?) -> String? {
        if let text = content as? String { return text }
        guard let parts = content as? [[String: Any]] else { return nil }
        let text = parts.compactMap { part -> String? in
            guard ["text", "output_text", "input_text"].contains(part["type"] as? String ?? "") else {
                return nil
            }
            return part["text"] as? String
        }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private static func preview(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
    }

    private static func hasToolUse(_ content: Any?) -> Bool {
        (content as? [[String: Any]])?.contains { $0["type"] as? String == "tool_use" } ?? false
    }

    private static func hasToolResult(_ content: Any?) -> Bool {
        (content as? [[String: Any]])?.contains { $0["type"] as? String == "tool_result" } ?? false
    }

    private static func hasOpenClawToolCall(_ content: Any?) -> Bool {
        (content as? [[String: Any]])?.contains { $0["type"] as? String == "toolCall" } ?? false
    }
}
