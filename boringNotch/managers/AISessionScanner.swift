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
        return roots.flatMap { root, source in
            recentSessionFiles(in: root).compactMap { url, modifiedAt in
                let lines = readSessionLines(at: url)
                switch source {
                case .codex:
                    return parseCodex(lines: lines, file: url, modifiedAt: modifiedAt)
                case .claude:
                    return parseClaude(lines: lines, file: url, modifiedAt: modifiedAt)
                }
            }
        }
        .sorted { $0.lastActivity > $1.lastActivity }
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

    private static func recentSessionFiles(in root: URL) -> [(URL, Date)] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
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
        guard let head = try? handle.read(upToCount: 16 * 1024),
              let length = try? handle.seekToEnd() else { return [] }
        let tailOffset = length > 64 * 1024 ? length - 64 * 1024 : 0
        guard (try? handle.seek(toOffset: tailOffset)) != nil,
              let tail = try? handle.readToEnd() else { return [] }
        let headLines = String(decoding: head, as: UTF8.self).split(separator: "\n").map(String.init)
        let tailLines = String(decoding: tail, as: UTF8.self).split(separator: "\n").map(String.init)
        return headLines + tailLines
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
}
