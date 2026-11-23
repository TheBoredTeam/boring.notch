//
//  AgentStore.swift
//  boringNotch
//

import AppKit

@MainActor
final class AgentStore: ObservableObject {
    static let shared = AgentStore()

    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var lastFinished: Date?   // dernier Stop, pour l'état « terminé » de la pastille
    @Published private(set) var usage: [String: UsageLimits] = [:]   // par source (claude, codex...)

    private static let key = "agentSessions"

    /// Sessions restaurées au lancement (état inconnu = terminé) pour ne pas perdre les conversations
    /// ouvertes quand l'app redémarre ; elles se remettent à jour à leur prochain événement.
    private struct Saved: Codable {
        var id, source: String
        var cwd, title, app, link, lastMessage: String?
        var awaitsReply: Bool?
        var startedAt, updatedAt: Date
    }

    private static let usageKey = "agentUsage"
    private var noiseIDs: Set<String> = []   // sessions techniques ignorées jusqu'au prochain lancement

    init() {
        usage = (UserDefaults.standard.data(forKey: Self.usageKey)).flatMap { try? JSONDecoder().decode([String: UsageLimits].self, from: $0) } ?? [:]
        let saved = (UserDefaults.standard.data(forKey: Self.key)).flatMap { try? JSONDecoder().decode([Saved].self, from: $0) } ?? []
        sessions = saved.filter { Date().timeIntervalSince($0.updatedAt) < 24 * 3600 && !AgentSession.isNoise($0.title) }.map {
            var s = AgentSession(id: $0.id, source: $0.source, cwd: $0.cwd, startedAt: $0.startedAt, updatedAt: $0.updatedAt)
            s.title = $0.title; s.app = $0.app; s.link = $0.link; s.state = .done; s.awaitsReply = $0.awaitsReply ?? false; s.lastMessage = $0.lastMessage
            return s
        }
    }

    private func save() {
        let saved = sessions.map { Saved(id: $0.id, source: $0.source, cwd: $0.cwd, title: $0.title, app: $0.app, link: $0.link, lastMessage: $0.lastMessage, awaitsReply: $0.awaitsReply,
                                         startedAt: $0.startedAt, updatedAt: $0.updatedAt) }
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.key)
    }

    /// Une conversation au repos dont le dernier message attend une réponse (à ne pas oublier).
    var needsReply: Bool { sessions.contains { $0.awaitsReply && !$0.isActive && Date().timeIntervalSince($0.updatedAt) < 4 * 3600 } }

    /// Heuristique : la fin du message pose une question ou invite à répondre.
    static func asksForReply(_ text: String?) -> Bool {
        guard let text else { return false }
        let tail = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.suffix(2)
        let junk = CharacterSet(charactersIn: "*_)\"'`»” ")
        if tail.contains(where: { $0.trimmingCharacters(in: junk).hasSuffix("?") }) { return true }
        let l = (tail.last ?? "").lowercased()
        return ["let me know", "dis-moi", "dites-moi", "tu veux que", "voulez-vous", "veux-tu"].contains { l.contains($0) }
    }

    /// Fin du message, sans balisage Markdown : c'est là que l'agent pose sa question.
    static func excerpt(_ text: String?) -> String? {
        guard let text else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let tail = lines.suffix(2).joined(separator: " ")
            .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "## ", with: "").replacingOccurrences(of: "- ", with: "")
        return tail.isEmpty ? nil : String(tail.suffix(240))
    }

    var activeCount: Int { sessions.filter(\.isActive).count }
    var needsAttention: Bool { sessions.contains { $0.state == .waiting && Date().timeIntervalSince($0.updatedAt) < 600 } }

    /// Session vers laquelle ramène la pastille : validation en attente > au travail > la plus récente.
    var focusSession: AgentSession? {
        sessions.first { $0.state == .waiting } ?? sessions.first { $0.isActive } ?? sessions.first
    }

    static let t3Code = "com.t3tools.t3code"

    /// Ramène à la conversation : le fil exact dans T3 Code (lien profond), sinon l'app qui l'héberge.
    /// ponytail: hors T3 Code, active l'app seulement ; sélectionner l'onglet exact demanderait AppleScript par terminal.
    func openTerminal(_ s: AgentSession) {
        if let link = s.link.flatMap(URL.init(string:)), NSWorkspace.shared.open(link) { return }
        // T3 Code est l'outil privilégié : app par défaut quand celle de la session n'est pas connue.
        let id = s.app ?? Self.t3Code
        // openApplication active aussi une app déjà lancée ; NSRunningApplication.activate est ignoré depuis une app non active.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }

    /// Réponses en attente d'une décision, par session (hook PermissionRequest bloquant).
    private var responders: [String: (String?) -> Void] = [:]

    /// Autoriser / refuser (ou approuver le plan) depuis le notch : renvoie la décision au hook,
    /// qui l'emballe pour l'agent (scripts/agent-permission.sh).
    func decide(_ sid: String, allow: Bool) {
        respond(sid, allow ? ["behavior": "allow"] : ["behavior": "deny", "message": "Refusé depuis Boring Notch"])
    }

    /// Réponses à AskUserQuestion : texte de la question -> libellé(s) choisi(s), séparés par des virgules.
    func answer(_ sid: String, _ answers: [String: String]) {
        respond(sid, ["behavior": "allow", "answers": answers])
    }

    private func respond(_ sid: String, _ decision: [String: Any]) {
        guard let r = responders.removeValue(forKey: sid),
              let json = try? JSONSerialization.data(withJSONObject: decision) else { return }
        r(String(decoding: json, as: UTF8.self))
        guard var s = sessions.first(where: { $0.id == sid }) else { return }
        s.ask = nil; s.questions = nil; s.plan = nil; s.state = .thinking
        upsert(s)
    }

    func apply(_ env: AgentEnvelope, reply: ((String?) -> Void)? = nil) {
        let p = env.payload
        if let l = p.rate_limits { applyUsage(l, source: env.source) }
        guard let sid = p.session_id, !noiseIDs.contains(sid) else { return }
        if AgentSession.isNoise(p.prompt) {
            noiseIDs.insert(sid)
            sessions.removeAll { $0.id == sid }
            save()
            return
        }

        // Titre du fil T3 Code (généré ou renommé) : remplace le premier prompt, sans réordonner la liste.
        if env.kind == "title" {
            guard let t = env.title, !t.isEmpty, let i = sessions.firstIndex(where: { $0.id == sid }), sessions[i].title != t else { return }
            sessions[i].title = t
            save()
            return
        }

        // Une nouvelle session vue via la status line est inactive (état .done) jusqu'à son prochain événement.
        var s = sessions.first { $0.id == sid }
            ?? AgentSession(id: sid, source: env.source, cwd: p.cwd, state: .done, startedAt: .now, updatedAt: .now)
        s.cwd = p.cwd ?? s.cwd
        s.app = env.app.flatMap { $0.isEmpty ? nil : $0 } ?? s.app
        s.link = env.link.flatMap { $0.isEmpty ? nil : $0 } ?? s.link
        if env.kind == "statusline" { upsert(s); return }
        if let f = p.tool_input?.file_path { s.file = f }
        let wasWaiting = s.state == .waiting
        s.ask = nil; s.questions = nil; s.plan = nil
        s.awaitsReply = false
        // Une autre activité de la session = la validation a été traitée ailleurs (terminal) : on libère le hook.
        if p.hook_event_name != "PermissionRequest" { responders.removeValue(forKey: sid)?(nil) }

        switch p.hook_event_name {
        case "UserPromptSubmit":
            if s.title == nil, let t = p.prompt?.split(whereSeparator: \.isNewline).first { s.title = String(t) }
            s.state = .thinking
        case "PreToolUse":
            s.state = .running(tool: p.tool_name ?? "…")
            startStep(&s, p)
        case "PostToolUse":
            s.state = .thinking
            finishStep(&s, p)
        case "PermissionRequest":
            s.state = .waiting
            if let reply { responders.removeValue(forKey: sid)?(nil); responders[sid] = reply }
            s.ask = PermissionAsk(agent: s.source.capitalized, tool: p.tool_name ?? "…", input: p.tool_input)
            s.canAnswer = reply != nil
            // Sans hook bloquant (reply nil), le notch ne peut pas répondre : simple validation à faire au terminal.
            if reply != nil, p.tool_name == "AskUserQuestion" { s.questions = p.tool_input?.questions }
            if reply != nil, p.tool_name == "ExitPlanMode" { s.plan = p.tool_input?.plan }
            if !wasWaiting { NSSound(named: "Glass")?.play() }
        case "Stop":
            s.state = .done
            s.awaitsReply = Self.asksForReply(p.last_assistant_message)
            s.lastMessage = Self.excerpt(p.last_assistant_message)
            lastFinished = .now
            for i in s.steps.indices where !s.steps[i].done { s.steps[i].duration = Date().timeIntervalSince(s.steps[i].started) }
        case "SessionEnd":
            sessions.removeAll { $0.id == sid }
            save()
            return
        default: break
        }
        s.updatedAt = .now
        // Pre/PostToolUse arrivent par centaines et ne changent rien de ce qui est sauvegardé : pas d'écriture disque.
        upsert(s, persist: !["PreToolUse", "PostToolUse"].contains(p.hook_event_name))
    }

    /// Met la session en tête de liste (ou la crée) sans toucher à son état.
    private func upsert(_ s: AgentSession, persist: Bool = true) {
        var s = s
        let known = sessions.contains { $0.id == s.id }
        if known, s.state == .done { s.updatedAt = .now }
        sessions.removeAll { $0.id == s.id }
        sessions.insert(s, at: 0)
        if persist || !known { save() }
    }

    // MARK: Étapes

    private func startStep(_ s: inout AgentSession, _ p: AgentEnvelope.Payload) {
        let tool = p.tool_name ?? "…"
        let input = p.tool_input
        let file = input?.file_path
        s.steps.append(AgentStep(id: p.tool_use_id ?? UUID().uuidString, tool: tool,
                                 label: Self.label(tool, input), file: file, started: .now))
        if s.steps.count > 30 { s.steps.removeFirst(s.steps.count - 30) }

        // Lignes modifiées : estimation à partir des chaînes de l'outil (ponytail: pas un vrai diff).
        guard let file, ["Edit", "Write", "MultiEdit"].contains(tool) else { return }
        func lines(_ t: String?) -> Int { t.map { $0.split(separator: "\n", omittingEmptySubsequences: false).count } ?? 0 }
        var d = s.diffs[file] ?? LineDiff()
        for e in input?.edits ?? [] { d.added += lines(e.new_string); d.removed += lines(e.old_string) }
        d.added += lines(input?.new_string) + lines(input?.content)
        d.removed += lines(input?.old_string)
        s.diffs[file] = d
    }

    private func finishStep(_ s: inout AgentSession, _ p: AgentEnvelope.Payload) {
        let i = s.steps.lastIndex { p.tool_use_id != nil ? $0.id == p.tool_use_id : ($0.tool == p.tool_name && !$0.done) }
        if let i { s.steps[i].duration = Date().timeIntervalSince(s.steps[i].started) }
    }

    private static func label(_ tool: String, _ i: AgentEnvelope.ToolInput?) -> String {
        if let f = i?.file_path { return "\(tool) \((f as NSString).lastPathComponent)" }
        let text = i?.description ?? i?.command?.split(whereSeparator: \.isNewline).first.map {
            String($0).components(separatedBy: "&&").last?.trimmingCharacters(in: .whitespaces) ?? String($0)   // sans le « cd … && » de tête
        }
        if tool == "Bash", let text { return "Run \(text.prefix(40))" }
        if let q = i?.pattern ?? text { return "\(tool) \(q.prefix(40))" }
        return tool
    }

    // MARK: Limites

    private func applyUsage(_ l: AgentEnvelope.Limits, source: String) {
        func map(_ w: AgentEnvelope.Window?) -> RateLimit? {
            w?.used_percentage.map { RateLimit(usedPercent: $0, resetsAt: w?.resets_at?.date) }
        }
        let old = usage[source]
        usage[source] = UsageLimits(fiveHour: map(l.five_hour) ?? old?.fiveHour,
                                    sevenDay: map(l.seven_day) ?? old?.sevenDay,
                                    updatedAt: .now)
        UserDefaults.standard.set(try? JSONEncoder().encode(usage), forKey: Self.usageKey)   // survit au redémarrage de l'app
    }
}
