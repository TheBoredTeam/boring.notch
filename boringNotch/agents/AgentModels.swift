//
//  AgentModels.swift
//  boringCode
//
//  Modelo de sessões de agentes de IA (Claude Code) exibidas no notch.
//  Estados e eventos inspirados no Open Island
//  (github.com/Octane0411/open-vibe-island), GPL-3.0.
//

import Foundation

enum AgentSessionStatus: String, Equatable {
    /// Sessão aberta, esperando o próximo prompt.
    case idle
    case running
    case waitingApproval
    /// O agente fez uma pergunta (AskUserQuestion, plano) que só dá pra responder no terminal.
    case waitingInput
    case done
    case error

    /// Algo que merece o indicador no notch fechado.
    var isActive: Bool {
        switch self {
        case .running, .waitingApproval, .waitingInput: true
        case .idle, .done, .error: false
        }
    }

    /// Ordem de prioridade do indicador: o que precisa de você vem primeiro.
    var priority: Int {
        switch self {
        case .waitingApproval: 5
        case .waitingInput: 4
        case .error: 3
        case .running: 2
        case .done: 1
        case .idle: 0
        }
    }

    var label: String {
        switch self {
        case .idle: String(localized: "Ready", comment: "Agent session status")
        case .running: String(localized: "Running", comment: "Agent session status")
        case .waitingApproval: String(localized: "Needs approval", comment: "Agent session status")
        case .waitingInput: String(localized: "Waiting for you", comment: "Agent session status")
        case .done: String(localized: "Done", comment: "Agent session status")
        case .error: String(localized: "Error", comment: "Agent session status")
        }
    }
}

/// Qual agente de IA é a sessão.
enum AgentKind: String, Equatable, CaseIterable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// Caminho do hook (`/hook/<agente>/<evento>`) → agente. Sem agente = Claude (hooks antigos).
    init(pathComponent: String?) {
        self = pathComponent.flatMap(AgentKind.init(rawValue:)) ?? .claude
    }
}

/// Onde a sessão está rodando — decide como "voltar pra ela".
enum AgentHost: Equatable {
    case terminal
    case iTerm
    case vsCode(bundleID: String)
    case claudeDesktop
    case codexDesktop
    case other(name: String, bundleID: String?)
    case unknown

    var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .iTerm: "iTerm"
        case .vsCode(let bundleID):
            switch bundleID {
            case "com.todesktop.230313mzl4w4u92": "Cursor"
            case "com.microsoft.VSCodeInsiders": "VS Code Insiders"
            default: "VS Code"
            }
        case .claudeDesktop: "Claude"
        case .codexDesktop: "Codex"
        case .other(let name, _): name
        case .unknown: "Claude Code"
        }
    }

    var bundleID: String? {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iTerm: "com.googlecode.iterm2"
        case .vsCode(let bundleID): bundleID
        case .claudeDesktop: "com.anthropic.claudefordesktop"
        case .codexDesktop: "com.openai.codex"
        case .other(_, let bundleID): bundleID
        case .unknown: nil
        }
    }

    /// Resolve o host a partir do ambiente do processo do hook.
    static func resolve(termProgram: String?, bundleID: String?, entrypoint: String?) -> AgentHost {
        let bundle = bundleID?.trimmingCharacters(in: .whitespaces) ?? ""
        let term = termProgram?.lowercased() ?? ""

        if entrypoint == "claude-desktop" || bundle == "com.anthropic.claudefordesktop" {
            return .claudeDesktop
        }
        let lowerBundle = bundle.lowercased()
        if lowerBundle == "com.openai.codex" || (lowerBundle.contains("openai") && lowerBundle.contains("codex")) {
            return .codexDesktop
        }
        if entrypoint == "claude-vscode" || term.hasPrefix("vscode") {
            let vsBundle = bundle.isEmpty ? "com.microsoft.VSCode" : bundle
            return .vsCode(bundleID: vsBundle)
        }
        switch (term, bundle) {
        case ("apple_terminal", _), (_, "com.apple.Terminal"): return .terminal
        case ("iterm.app", _), (_, "com.googlecode.iterm2"): return .iTerm
        default: break
        }
        if !term.isEmpty || !bundle.isEmpty {
            return .other(name: termProgram ?? bundle, bundleID: bundle.isEmpty ? nil : bundle)
        }
        return .unknown
    }
}

struct AgentPermissionRequest: Equatable {
    let id: UUID
    let toolName: String
    /// Resumo legível do que será executado (comando, arquivo, URL…).
    let summary: String
    let receivedAt: Date
}

/// Uma pergunta do AskUserQuestion do Claude Code.
struct AgentQuestion: Equatable, Identifiable {
    struct Option: Equatable, Identifiable {
        let label: String
        let description: String?
        var id: String { label }
    }

    let question: String
    let header: String?
    let options: [Option]
    let multiSelect: Bool
    var id: String { question }
}

/// Perguntas aguardando resposta. `toolInput` é o JSON original, devolvido com as respostas.
struct AgentPendingQuestion: Equatable {
    let id: UUID
    let questions: [AgentQuestion]
    let toolInput: Data
    let receivedAt: Date

    /// Lê `tool_input.questions[]` (question, header, options[].label/description, multiSelect).
    init?(id: UUID, toolInputJSON: Data, receivedAt: Date) {
        guard let object = try? JSONSerialization.jsonObject(with: toolInputJSON) as? [String: Any],
              let rawQuestions = object["questions"] as? [[String: Any]] else { return nil }
        let questions: [AgentQuestion] = rawQuestions.compactMap { raw in
            guard let text = raw["question"] as? String, !text.isEmpty else { return nil }
            let options = (raw["options"] as? [[String: Any]] ?? []).compactMap { option -> AgentQuestion.Option? in
                guard let label = option["label"] as? String, !label.isEmpty else { return nil }
                return .init(label: label, description: option["description"] as? String)
            }
            return AgentQuestion(
                question: text,
                header: raw["header"] as? String,
                options: options,
                multiSelect: raw["multiSelect"] as? Bool ?? false
            )
        }
        guard !questions.isEmpty else { return nil }
        self.id = id
        self.questions = questions
        self.toolInput = toolInputJSON
        self.receivedAt = receivedAt
    }
}

struct AgentSession: Identifiable, Equatable {
    let id: String
    var agent: AgentKind = .claude
    var cwd: String
    var status: AgentSessionStatus
    var host: AgentHost
    var tty: String?
    /// PID do processo `claude` — usado para detectar sessões que morreram sem SessionEnd.
    var agentPID: Int32?
    var lastPrompt: String?
    /// Linha curta do que está acontecendo agora ("Bash · npm test").
    var activity: String?
    var errorMessage: String?
    /// Fila de pedidos de permissão ainda sem resposta (o primeiro é o exibido).
    var pendingPermissions: [AgentPermissionRequest] = []
    var subagents: Int = 0
    var startedAt: Date
    var updatedAt: Date

    var pendingQuestion: AgentPendingQuestion?

    var pendingPermission: AgentPermissionRequest? { pendingPermissions.first }

    /// Algo esperando você responder no notch (aprovação ou pergunta).
    var needsAnswer: Bool { pendingPermission != nil || pendingQuestion != nil }

    /// "Claude · Terminal", "Codex · iTerm", "Codex" (app), "Claude" (app).
    var hostLabel: String {
        switch host {
        case .claudeDesktop, .codexDesktop, .unknown: agent.displayName
        default: "\(agent.displayName) · \(host.displayName)"
        }
    }

    var projectName: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? cwd : name
    }
}

// MARK: - Payload dos hooks

/// Subconjunto do JSON que o Claude Code manda no stdin de cada hook.
struct ClaudeHookPayload: Decodable {
    let sessionID: String
    let hookEventName: String
    let cwd: String?
    let transcriptPath: String?
    let toolName: String?
    let toolInput: JSONValue?
    let prompt: String?
    let message: String?
    let notificationType: String?
    let error: String?
    let errorDetails: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case transcriptPath = "transcript_path"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case prompt, message
        case notificationType = "notification_type"
        case error
        case errorDetails = "error_details"
    }
}

/// JSON genérico, só para ler `tool_input` sem conhecer cada ferramenta.
enum JSONValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    /// String do campo — ou, se for lista de strings (o `command` do Codex), o último item
    /// (`["bash", "-lc", "npm test"]` → "npm test").
    subscript(key: String) -> String? {
        guard case .object(let dict) = self, let value = dict[key] else { return nil }
        switch value {
        case .string(let string): return string
        case .array(let items):
            let strings = items.compactMap { item -> String? in
                if case .string(let string) = item { return string }
                return nil
            }
            return strings.last
        default: return nil
        }
    }
}

extension ClaudeHookPayload {
    /// "Bash · npm test", "Edit · ContentView.swift", "WebFetch · docs.swift.org".
    var toolSummary: String? {
        guard let toolName else { return nil }
        guard let detail = toolDetail, !detail.isEmpty else { return toolName }
        return "\(toolName) · \(detail)"
    }

    var toolDetail: String? {
        guard let input = toolInput else { return nil }
        if let command = input["command"] { return command.singleLine }
        if let path = input["file_path"] ?? input["notebook_path"] ?? input["path"] {
            return (path as NSString).lastPathComponent
        }
        if let url = input["url"] { return URL(string: url)?.host ?? url }
        if let pattern = input["pattern"] { return pattern.singleLine }
        if let description = input["description"] { return description.singleLine }
        if let query = input["query"] { return query.singleLine }
        return nil
    }
}

extension String {
    var singleLine: String {
        split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? self
    }
}
