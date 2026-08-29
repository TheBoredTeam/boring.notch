//
//  AgentWire.swift
//  boringNotch
//
//  Wire models shared with the Claude Code hook integration
//  (~/.claude/hooks/boring-notch/boring-notify.sh + boring-decide.sh).
//
//  Hook scripts → App (HTTP POST /v1/hook, JSON body):
//    the raw Claude Code hook payload:
//      { hook_event_name, session_id, cwd, transcript_path,
//        tool_name?, tool_input?, prompt?, message?, stop_hook_active? }
//
//  App → Hook script (HTTP response body, PreToolUse only):
//    a Claude Code hookSpecificOutput JSON (permissionDecision allow/deny),
//    or an empty body meaning "no decision — fall through to the normal
//    permission flow".
//

import Foundation

// MARK: - Type-erased JSON value

indirect enum AgentJSON: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AgentJSON])
    case array([AgentJSON])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Double.self) { self = .number(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([String: AgentJSON].self) { self = .object(v); return }
        if let v = try? container.decode([AgentJSON].self) { self = .array(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var string: String? { if case .string(let v) = self { v } else { nil } }
    var number: Double? { if case .number(let v) = self { v } else { nil } }
    var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    var object: [String: AgentJSON]? { if case .object(let v) = self { v } else { nil } }
    var array: [AgentJSON]? { if case .array(let v) = self { v } else { nil } }

    subscript(key: String) -> AgentJSON? { object?[key] }
    subscript(index: Int) -> AgentJSON? {
        guard let a = array, a.indices.contains(index) else { return nil }
        return a[index]
    }

    static func decode<T: Decodable>(_ type: T.Type, from value: AgentJSON?) -> T? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(type.self, from: data)
    }
}

// MARK: - Live instance (a Claude Code process that fired hooks)

struct AgentInstanceInfo: Identifiable, Equatable {
    let id: String          // session id reported by the hook
    var directory: String
    var pid: Int?
    var managed: Bool
    var lastSeen: Date

    var shortDirectory: String {
        (directory as NSString).lastPathComponent
    }
}

// MARK: - Events (normalized from hook payloads)

enum AgentEvent: Equatable {
    case sessionStarted(sessionID: String, directory: String?)
    case sessionEnded(sessionID: String)
    case promptSubmitted(sessionID: String, text: String)
    case toolUsed(sessionID: String, tool: String, detail: String?)
    case stopped(sessionID: String, reply: String?)
    case attention(sessionID: String, message: String)
    case errored(sessionID: String, message: String)
}

// MARK: - Pending user action: permission

struct AgentPendingPermission: Identifiable, Equatable {
    let id: String            // bridge-generated request id
    let sessionID: String
    let tool: String
    var title: String         // human label, e.g. "Bash command"
    var detail: String        // command line or file path
    var input: AgentJSON?
    var directory: String?
    var arrivedAt: Date
}

// MARK: - Questions (AskUserQuestion interception)

struct AgentQuestionOption: Identifiable, Equatable {
    let label: String
    let detail: String
    var id: String { label }
}

struct AgentQuestionItem: Identifiable, Equatable {
    let question: String
    let header: String
    let options: [AgentQuestionOption]
    var multiple: Bool
    var id: String { header.isEmpty ? question : header }

    /// Builds from the AskUserQuestion tool_input shape:
    /// { questions: [ { question, header, options: [ { label, description } ], multiSelect } ] }
    static func parse(_ json: AgentJSON) -> AgentQuestionItem? {
        guard let question = json["question"]?.string else { return nil }
        let options = (json["options"]?.array ?? []).compactMap { opt -> AgentQuestionOption? in
            guard let label = opt["label"]?.string else { return nil }
            return AgentQuestionOption(label: label, detail: opt["description"]?.string ?? "")
        }
        guard !options.isEmpty else { return nil }
        return AgentQuestionItem(
            question: question,
            header: json["header"]?.string ?? "",
            options: options,
            multiple: json["multiSelect"]?.bool ?? false)
    }
}

struct AgentPendingQuestion: Identifiable, Equatable {
    let id: String
    let sessionID: String
    var questions: [AgentQuestionItem]
    var directory: String?
    var arrivedAt: Date
}

// MARK: - Decisions (App → held PreToolUse request)

enum AgentDecision: Equatable {
    case allow
    case deny(reason: String?)
    /// AskUserQuestion answered from the notch. Carries one answer list per
    /// question, in the same order the questions were asked.
    case answers([[String]])
}

// MARK: - A parsed chat message ready for display.

struct AgentChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant, error, system }
    let id: String
    let role: Role
    let text: String
}