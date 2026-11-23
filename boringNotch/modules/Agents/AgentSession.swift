//
//  AgentSession.swift
//  boringNotch
//

import Foundation

enum AgentState: Equatable {
    case thinking
    case running(tool: String)
    case waiting          // en attente d'une approbation
    case done
}

/// Une action d'outil de l'agent (Read, Edit, Run…), affichée dans la liste de progression.
struct AgentStep: Identifiable, Equatable {
    let id: String
    var tool: String
    var label: String
    var file: String?
    var started: Date
    var duration: TimeInterval?
    var done: Bool { duration != nil }
    var isEdit: Bool { ["Edit", "Write", "MultiEdit"].contains(tool) }
}

struct LineDiff: Equatable {
    var added = 0
    var removed = 0
}

struct AgentSession: Identifiable, Equatable {
    let id: String              // session_id de l'agent
    var source: String          // claude, codex, cursor...
    var cwd: String?
    var title: String?          // premier prompt de la session
    var app: String?            // bundle id du terminal / IDE, pour rouvrir la conversation
    var link: String?           // t3code://threads/<env>/<fil> quand la session tourne dans T3 Code
    var ask: PermissionAsk?     // action en attente de validation, déjà mise en français
    var canAnswer = false       // le hook est bloquant : le notch peut répondre (sinon : au terminal)
    var questions: [AgentQuestion]?   // AskUserQuestion en attente de réponse
    var plan: String?                 // ExitPlanMode : plan (Markdown) en attente d'approbation
    var lastMessage: String?    // fin du dernier message de l'agent (extrait affiché au repos)
    var awaitsReply = false     // le dernier message de l'agent appelle une réponse de l'utilisateur
    var state: AgentState = .thinking
    var file: String?
    var steps: [AgentStep] = []
    var diffs: [String: LineDiff] = [:]   // par fichier, cumulé sur la session
    var startedAt: Date
    var updatedAt: Date

    var project: String {
        let name = cwd.map { ($0 as NSString).lastPathComponent } ?? ""
        return name.isEmpty || name == "/" ? "Sans projet" : name
    }
    /// Sessions techniques de T3 Code (titre du fil, message de commit, nom de branche, texte de PR, visite guidée) :
    /// jamais utiles à l'utilisateur. Débuts des prompts de T3 Code (provider-core, textGenerationPrompts.ts).
    static let noisePrefixes = ["Generate a title", "Regenerate the title for an existing T3 Code thread",
                                "You write concise git commit messages", "You write source control change request content",
                                "You generate concise git branch names", "You prepare a guided tour of change request"]
    static func isNoise(_ prompt: String?) -> Bool { prompt.map { p in noisePrefixes.contains { p.hasPrefix($0) } } ?? false }
    /// Où le clic ramène : T3 Code (outil privilégié) sauf session lancée depuis un autre terminal.
    var opensInT3: Bool { link != nil || app == nil || app == AgentStore.t3Code }
    var openLabel: String { opensInT3 ? "Ouvrir dans T3 Code" : "Ouvrir le terminal" }
    /// Sans événement depuis 5 min (interruption par Échap, terminal fermé : aucun hook Stop), la session est considérée inactive.
    var isActive: Bool { state != .done && Date().timeIntervalSince(updatedAt) < 300 }
}

/// Une question d'AskUserQuestion (1 à 4 par appel), telle que Claude Code l'envoie au hook.
struct AgentQuestion: Decodable, Equatable {
    struct Option: Decodable, Equatable {
        var label: String
        var description: String?
    }
    var question: String
    var header: String?
    var options: [Option]
    var multiSelect: Bool?
}

struct RateLimit: Equatable, Codable {
    var usedPercent: Double
    var resetsAt: Date?
}

struct UsageLimits: Equatable, Codable {
    var fiveHour: RateLimit?
    var sevenDay: RateLimit?
    var updatedAt = Date.distantPast

    /// Fenêtres encore valables : jusqu'à leur réinitialisation (après, le pourcentage ne veut plus rien dire).
    /// Sans date de réinitialisation : 6 h après la dernière réception. nil = rien à afficher.
    func current(at now: Date = .now) -> UsageLimits? {
        func valid(_ w: RateLimit?) -> RateLimit? {
            guard let w else { return nil }
            if let r = w.resetsAt { return r > now ? w : nil }
            return now.timeIntervalSince(updatedAt) < 6 * 3600 ? w : nil
        }
        let c = UsageLimits(fiveHour: valid(fiveHour), sevenDay: valid(sevenDay), updatedAt: updatedAt)
        return c.fiveHour == nil && c.sevenDay == nil ? nil : c
    }
}

/// Une ligne reçue des scripts : {"source":"claude","kind":"statusline"?,"payload":{...JSON de l'agent...}}
/// Les noms de champs suivent les payloads Claude Code ; Codex/Cursor seront ajoutés ici
/// (ponytail: un seul décodeur tolérant, pas un par agent).
struct AgentEnvelope: Decodable {
    struct Payload: Decodable {
        var session_id: String?
        var hook_event_name: String?
        var cwd: String?
        var prompt: String?
        var last_assistant_message: String?
        var tool_name: String?
        var tool_use_id: String?
        var tool_input: ToolInput?
        var rate_limits: Limits?
        // Commande terminal terminée (scripts/cmd-hook.zsh, kind "command").
        var command: String?
        var exit_code: Int?
        var duration: Double?
    }
    struct ToolInput: Decodable {
        var file_path: String?
        var command: String?
        var description: String?
        var pattern: String?
        var old_string: String?
        var new_string: String?
        var content: String?
        var edits: [Edit]?
        var questions: [AgentQuestion]?   // AskUserQuestion
        var plan: String?                 // ExitPlanMode
        var scalars: [String: String] = [:]   // tous les paramètres simples (url, query, ids d'un outil MCP…)

        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            func get<T: Decodable>(_ k: Key) -> T? { try? c.decode(T.self, forKey: k) }
            for k in c.allKeys {
                switch k.stringValue {
                case "file_path": file_path = get(k)
                case "command": command = get(k)
                case "description": description = get(k)
                case "pattern": pattern = get(k)
                case "old_string": old_string = get(k)
                case "new_string": new_string = get(k)
                case "content": content = get(k)
                case "edits": edits = get(k)
                case "questions": questions = get(k)
                case "plan": plan = get(k)
                default: break
                }
                if let v: String = get(k) { scalars[k.stringValue] = v }
                else if let v: Int = get(k) { scalars[k.stringValue] = String(v) }
                else if let v: Double = get(k) { scalars[k.stringValue] = String(v) }
                else if let v: Bool = get(k) { scalars[k.stringValue] = v ? "oui" : "non" }
            }
        }
    }
    struct Edit: Decodable {
        var old_string: String?
        var new_string: String?
    }
    struct Limits: Decodable {
        var five_hour: Window?
        var seven_day: Window?
    }
    struct Window: Decodable {
        var used_percentage: Double?
        var resets_at: Reset?

        /// resets_at : epoch (secondes) ou date ISO 8601, selon la version de l'agent.
        struct Reset: Decodable {
            let date: Date?
            init(from d: Decoder) throws {
                let c = try d.singleValueContainer()
                if let n = try? c.decode(Double.self) {
                    date = Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
                } else if let s = try? c.decode(String.self) {
                    date = ISO8601DateFormatter().date(from: s)
                } else {
                    date = nil
                }
            }
        }
    }
    var source: String
    var kind: String?
    var app: String?
    var link: String?        // lien profond T3 Code (scripts : T3CODE_THREAD_ID)
    var title: String?       // kind "title" : titre du fil T3 Code (scripts/t3-thread.sh)
    var wait: Bool?          // le hook attend une décision (PermissionRequest)
    var payload: Payload
}
