//
//  AgentSessionStore.swift
//  boringCode
//
//  Estado das sessões do Claude Code: recebe eventos dos hooks, deriva o
//  status de cada sessão e segura os pedidos de permissão até você responder.
//  Máquina de estados inspirada no reducer do Open Island
//  (github.com/Octane0411/open-vibe-island), GPL-3.0.
//

import AppKit
import Combine
import Defaults
import Foundation
import os

@MainActor
final class AgentSessionStore: ObservableObject {
    static let shared = AgentSessionStore()

    /// Mais recentes primeiro.
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var hookState: ClaudeHookInstaller.State = .notInstalled
    /// Muda a cada novo pedido de permissão — o notch observa para se expandir.
    @Published private(set) var expandRequest: UUID?
    /// Última vez que uma sessão terminou (Stop) — o indicador mostra um ✓ rápido.
    @Published private(set) var lastCompletion: Date?

    private let server = AgentHookServer()
    private var pendingConnections: [UUID: AgentHookConnection] = [:]
    private var housekeeping: Timer?
    private var enabledCancellable: AnyCancellable?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "boringcode", category: "AgentSessionStore")

    /// Por quanto tempo o ✓ de "concluído" fica no notch fechado.
    static let completionFlashDuration: TimeInterval = 5

    private init() {
        server.onRequest = { [weak self] request, connection in
            Task { @MainActor in self?.handle(request, connection: connection) }
        }
    }

    // MARK: - Ciclo de vida

    func start() {
        enabledCancellable = Defaults.publisher(.agentsEnabled)
            .sink { [weak self] change in
                Task { @MainActor in self?.applyEnabled(change.newValue) }
            }
    }

    private func applyEnabled(_ enabled: Bool) {
        if enabled {
            server.start()
            installHooksIfNeeded()
            housekeeping?.invalidate()
            housekeeping = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.pruneSessions() }
            }
        } else {
            housekeeping?.invalidate()
            housekeeping = nil
            resolveAllPending()
            server.stop()
            sessions = []
            refreshHookState()
            if BoringViewCoordinator.shared.currentView == .agents {
                BoringViewCoordinator.shared.currentView = .home
            }
        }
    }

    func installHooksIfNeeded() {
        do {
            try ClaudeHookInstaller.writeHookScript()
            switch ClaudeHookInstaller.currentState() {
            case .notInstalled, .outdated: try ClaudeHookInstaller.install()
            default: break
            }
        } catch {
            log.error("falha ao instalar hooks: \(error.localizedDescription)")
        }
        refreshHookState()
    }

    func reinstallHooks() {
        do { try ClaudeHookInstaller.install() } catch {
            log.error("falha ao reinstalar hooks: \(error.localizedDescription)")
        }
        refreshHookState()
    }

    func uninstallHooks() {
        do { try ClaudeHookInstaller.uninstall() } catch {
            log.error("falha ao remover hooks: \(error.localizedDescription)")
        }
        refreshHookState()
    }

    func refreshHookState() {
        hookState = ClaudeHookInstaller.currentState()
    }

    // MARK: - Consultas para a UI

    var activeSessions: [AgentSession] { sessions.filter { $0.status.isActive } }

    var pendingApprovalCount: Int { sessions.reduce(0) { $0 + $1.pendingPermissions.count } }

    /// O que o indicador do notch fechado deve mostrar (nil = nada, volta o espectro).
    var closedIndicatorStatus: AgentSessionStatus? {
        if let top = activeSessions.max(by: { $0.status.priority < $1.status.priority }) {
            return top.status
        }
        if let lastCompletion, Date().timeIntervalSince(lastCompletion) < Self.completionFlashDuration {
            return sessions.contains { $0.status == .error && $0.updatedAt >= lastCompletion } ? .error : .done
        }
        return nil
    }

    // MARK: - Ações

    func approve(_ sessionID: String) { resolveFirstPermission(of: sessionID, allow: true) }

    func deny(_ sessionID: String) { resolveFirstPermission(of: sessionID, allow: false) }

    func focus(_ session: AgentSession) {
        AgentTerminalFocus.focus(session)
    }

    func dismiss(_ sessionID: String) {
        guard let session = sessions.first(where: { $0.id == sessionID }), !session.status.isActive else { return }
        sessions.removeAll { $0.id == sessionID }
    }

    // MARK: - Eventos

    private func handle(_ request: AgentHookConnection.Request, connection: AgentHookConnection) {
        guard Defaults[.agentsEnabled],
              let payload = try? JSONDecoder().decode(ClaudeHookPayload.self, from: request.body) else {
            connection.respond(nil)
            return
        }

        let now = Date()
        var session = sessions.first(where: { $0.id == payload.sessionID }) ?? AgentSession(
            id: payload.sessionID,
            cwd: payload.cwd ?? "",
            status: .idle,
            host: .unknown,
            startedAt: now,
            updatedAt: now
        )
        if let cwd = payload.cwd, !cwd.isEmpty { session.cwd = cwd }
        session.updatedAt = now
        applyContext(request.headers, to: &session)

        var holdConnection = false

        switch payload.hookEventName {
        case "SessionStart":
            session.status = .idle
            session.activity = nil
        case "UserPromptSubmit":
            session.status = .running
            session.lastPrompt = payload.prompt?.singleLine
            session.activity = nil
            session.errorMessage = nil
        case "PreToolUse":
            session.status = session.pendingPermissions.isEmpty ? .running : .waitingApproval
            session.activity = payload.toolSummary
        case "PostToolUse", "PostToolUseFailure", "PermissionDenied":
            // A ferramenta rodou (ou foi negada): qualquer pedido pendente dela já foi decidido.
            dropPermissions(of: &session)
            session.status = .running
        case "PermissionRequest":
            if ["AskUserQuestion", "ExitPlanMode"].contains(payload.toolName ?? "") {
                // Precisa de resposta rica — segue pro diálogo normal do Claude.
                session.status = .waitingInput
                session.activity = payload.toolName == "ExitPlanMode" ? String(localized: "Plan ready for review") : String(localized: "Question for you")
            } else {
                let permission = AgentPermissionRequest(
                    id: UUID(),
                    toolName: payload.toolName ?? "Tool",
                    summary: payload.toolDetail ?? "",
                    receivedAt: now
                )
                session.pendingPermissions.append(permission)
                session.status = .waitingApproval
                pendingConnections[permission.id] = connection
                connection.onClientGone = { [weak self] in
                    // Respondido no terminal (ou Claude cancelou): tira do notch.
                    Task { @MainActor in self?.permissionAbandoned(permission.id, sessionID: session.id) }
                }
                holdConnection = true
                if Defaults[.agentsExpandOnApproval] { expandRequest = permission.id }
            }
        case "Notification":
            switch payload.notificationType {
            case "permission_prompt" where session.pendingPermissions.isEmpty:
                // Sem PermissionRequest (ex.: host que não dispara o hook) — só dá pra responder lá.
                session.status = .waitingInput
                session.activity = payload.message?.singleLine ?? String(localized: "Permission pending")
            case "elicitation_dialog", "agent_needs_input":
                session.status = .waitingInput
                session.activity = payload.message?.singleLine
            default:
                break
            }
        case "Stop":
            dropPermissions(of: &session)
            session.status = .done
            session.activity = nil
            session.subagents = 0
            lastCompletion = now
            scheduleIndicatorRefresh()
        case "StopFailure":
            dropPermissions(of: &session)
            session.status = .error
            session.errorMessage = (payload.error ?? payload.errorDetails ?? String(localized: "API request failed")).singleLine
            session.subagents = 0
            lastCompletion = now
            scheduleIndicatorRefresh()
        case "SubagentStart":
            session.subagents += 1
        case "SubagentStop":
            session.subagents = max(0, session.subagents - 1)
        case "PreCompact":
            session.status = .running
            session.activity = String(localized: "Compacting context")
        case "SessionEnd":
            dropPermissions(of: &session)
            sessions.removeAll { $0.id == session.id }
            connection.respond(nil)
            return
        default:
            break
        }

        upsert(session)
        if !holdConnection { connection.respond(nil) }
    }

    private func applyContext(_ headers: [String: String], to session: inout AgentSession) {
        if let tty = headers["x-bc-tty"], !tty.isEmpty { session.tty = tty }
        if let pid = headers["x-bc-pid"].flatMap(Int32.init) { session.agentPID = pid }
        let host = AgentHost.resolve(
            termProgram: headers["x-bc-term"],
            bundleID: headers["x-bc-bundle"],
            entrypoint: headers["x-bc-entrypoint"]
        )
        if host != .unknown { session.host = host }
    }

    private func upsert(_ session: AgentSession) {
        sessions.removeAll { $0.id == session.id }
        sessions.insert(session, at: 0)
    }

    // MARK: - Permissões

    private func resolveFirstPermission(of sessionID: String, allow: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              let permission = sessions[index].pendingPermission else { return }
        let decision: [String: Any] = allow
            ? ["behavior": "allow"]
            : ["behavior": "deny", "message": "Denied by the user from the boringCode notch."]
        let output: [String: Any] = [
            "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]
        ]
        let body = try? JSONSerialization.data(withJSONObject: output)
        pendingConnections.removeValue(forKey: permission.id)?.respond(body)

        sessions[index].pendingPermissions.removeFirst()
        sessions[index].status = sessions[index].pendingPermissions.isEmpty ? .running : .waitingApproval
        sessions[index].updatedAt = Date()
    }

    private func permissionAbandoned(_ permissionID: UUID, sessionID: String) {
        pendingConnections[permissionID] = nil
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].pendingPermissions.removeAll { $0.id == permissionID }
        if sessions[index].pendingPermissions.isEmpty, sessions[index].status == .waitingApproval {
            sessions[index].status = .running
        }
    }

    private func dropPermissions(of session: inout AgentSession) {
        for permission in session.pendingPermissions {
            pendingConnections.removeValue(forKey: permission.id)?.respond(nil)
        }
        session.pendingPermissions.removeAll()
    }

    private func resolveAllPending() {
        pendingConnections.values.forEach { $0.respond(nil) }
        pendingConnections.removeAll()
    }

    // MARK: - Limpeza

    private func scheduleIndicatorRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.completionFlashDuration + 0.1) { [weak self] in
            self?.objectWillChange.send()
        }
    }

    /// Tira sessões cujo processo morreu sem SessionEnd e concluídas antigas.
    private func pruneSessions() {
        let now = Date()
        let before = sessions.count
        sessions.removeAll { session in
            if let pid = session.agentPID, kill(pid, 0) != 0, errno == ESRCH {
                for permission in session.pendingPermissions {
                    pendingConnections.removeValue(forKey: permission.id)?.respond(nil)
                }
                return true
            }
            let age = now.timeIntervalSince(session.updatedAt)
            switch session.status {
            case .done, .error: return age > 30 * 60
            case .idle: return age > 2 * 60 * 60
            default: return false
            }
        }
        if sessions.count != before { log.debug("removidas \(before - self.sessions.count) sessões") }
    }
}
