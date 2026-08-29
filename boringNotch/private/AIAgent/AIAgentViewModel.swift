//
//  AIAgentViewModel.swift
//  boringNotch
//
//  Central state for the Claude Code integration: live sessions from
//  ~/.claude/projects transcripts, hook-driven approval/question cards,
//  chat driving through headless `claude -p` runs, and model switching.
//

import Foundation
import Combine
import Defaults
import AppKit
import SwiftUI

// MARK: - Session model

struct AgentSession: Identifiable, Equatable {
    enum Phase: Equatable {
        case busy
        case idle
        case waitingApproval
        case waitingAnswer
        case errored
    }

    enum Source: Equatable {
        case managed    // driven from the notch (headless claude -p runs)
        case external   // user's own terminal session, observed via hooks/transcripts
    }

    let id: String
    var directory: String?
    var title: String
    var phase: Phase = .idle
    var source: Source = .external
    var lastPrompt: String?
    var lastReply: String?
    var lastTool: String?
    var modelRef: String?
    var updatedAt = Date()
    var needsFirstPrompt = false

    var project: String {
        guard let dir = directory, !dir.isEmpty else { return "claude" }
        return (dir as NSString).lastPathComponent
    }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            return lastPrompt.map { String($0.prefix(48)) } ?? "Session \(id.suffix(6))"
        }
        return String(t.prefix(64))
    }

    static func == (lhs: AgentSession, rhs: AgentSession) -> Bool {
        lhs.id == rhs.id && lhs.phase == rhs.phase && lhs.title == rhs.title
    }
}

// MARK: - Done notification card

struct AgentDoneCard: Identifiable, Equatable {
    let id = UUID()
    let sessionID: String
    var title: String
    var reply: String
    var isAttention = false
    var createdAt = Date()
}

// MARK: - Model picker entry

struct AgentModel: Identifiable, Equatable {
    let id: String
    let providerID: String
    let name: String?

    var ref: String { "\(providerID)/\(id)" }
}

// MARK: - View model

@MainActor
final class AIAgentViewModel: ObservableObject, AgentBridgeDelegate {
    static let shared = AIAgentViewModel()

    let bridge = AgentBridgeServer()

    // Environment
    @Published private(set) var instances: [AgentInstanceInfo] = []
    @Published private(set) var connected = false
    @Published private(set) var everConnected = false
    @Published private(set) var claudeBinary = ""
    @Published private(set) var authState: ClaudeAuthState = .needsAuth

    // Sessions
    @Published private(set) var sessions: [AgentSession] = []
    @Published var selectedSessionID: String?

    // Pending user action
    @Published private(set) var pendingPermissions: [AgentPendingPermission] = []
    @Published private(set) var pendingQuestions: [AgentPendingQuestion] = []
    @Published private(set) var doneCards: [AgentDoneCard] = []
    @Published var cardDismissedIDs: Set<String> = []

    // Chat state
    @Published private(set) var messages: [AgentChatMessage] = []
    @Published private(set) var chatLoading = false
    @Published private(set) var sending = false
    @Published private(set) var availableModels: [AgentModel] = []
    /// Prompts typed while the session is busy in the terminal, keyed by
    /// session; flushed automatically the moment the session goes idle.
    /// Persisted so an app relaunch doesn't eat messages waiting to send.
    @Published private(set) var queuedPrompts: [String: [String]] = AIAgentViewModel.restoreQueuedPrompts() {
        didSet { persistQueuedPrompts() }
    }

    private var runners: [String: ClaudeCodeRunner] = [:]
    private var refreshTimer: Timer?
    private var slowTimer: Timer?
    private var reloadDebounce: Task<Void, Never>?
    private var doneCardCleanupTask: Task<Void, Never>?
    private var started = false
    private var scanInFlight = false

    var hasPendingApproval: Bool {
        !pendingPermissions.isEmpty || !pendingQuestions.isEmpty
    }

    /// The card that should take over the open notch surface, if any.
    var activePermission: AgentPendingPermission? {
        pendingPermissions.first { !cardDismissedIDs.contains($0.id) }
    }

    var activeQuestion: AgentPendingQuestion? {
        pendingQuestions.first { !cardDismissedIDs.contains($0.id) }
    }

    var activeDoneCard: AgentDoneCard? {
        doneCards.first
    }

    /// True while a card worth interrupting the user for is on screen —
    /// drives the notch auto-open and its vertical expansion.
    var hasActiveAgentCard: Bool {
        activePermission != nil || activeQuestion != nil || activeDoneCard != nil
    }

    /// Attention sound for a card arriving in the notch. Both sounds are
    /// user-configurable in the agent settings (system sounds by name).
    private func playArrivalSound(done: Bool) {
        let name = done ? Defaults[.aiAgentDoneSound] : Defaults[.aiAgentArrivalSound]
        NSSound(named: NSSound.Name(name))?.play()
    }

    var selectedSession: AgentSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    var needsAuth: Bool { authState == .needsAuth }
    var claudeMissing: Bool { claudeBinary.isEmpty }

    // MARK: Lifecycle

    func activate() {
        guard Defaults[.aiAgentEnabled] else { return }
        guard !started else { return }
        started = true

        let ok = bridge.start(delegate: self)
        if !ok {
            NSLog("[Agent] failed to start bridge server")
        }
        AgentHookInstaller.ensureInstalled()
        refreshEnvironment()
        loadModels()
        refreshSessions()
        startTimers()
    }

    func deactivate() {
        stopTimers()
        bridge.stop()
        started = false
    }

    func restart() {
        deactivate()
        activate()
    }

    private func startTimers() {
        refreshTimer?.invalidate()
        slowTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshSessions() }
        }
        slowTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshEnvironment()
                Task { @MainActor [weak self] in self?.loadModels() }
            }
        }
    }

    private func stopTimers() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        slowTimer?.invalidate()
        slowTimer = nil
    }

    private func refreshEnvironment() {
        claudeBinary = ClaudeCodeRunner.resolveBinary()
        authState = ClaudeCodeRunner.authState()
    }

    // MARK: Sessions refresh (from transcripts + live state)

    /// Runs the transcript scan off the main thread — it stats every session
    /// file and re-reads changed ones — then applies the result on the main
    /// actor. Overlapping scans are skipped; the next timer tick picks up.
    private func refreshSessions() {
        guard !scanInFlight else { return }
        scanInFlight = true
        Task.detached(priority: .utility) { [weak self] in
            let summaries = TranscriptStore.scan()
            await MainActor.run { [weak self] in
                self?.applyScan(summaries)
                self?.scanInFlight = false
            }
        }
    }

    private func applyScan(_ summaries: [TranscriptStore.Summary]) {
        let now = Date()

        for summary in summaries {
            var phase: AgentSession.Phase = .idle
            if pendingPermissions.contains(where: { $0.sessionID == summary.id }) {
                phase = .waitingApproval
            } else if pendingQuestions.contains(where: { $0.sessionID == summary.id }) {
                phase = .waitingAnswer
            } else if runners[summary.id] != nil || now.timeIntervalSince(summary.updatedAt) < 25 {
                phase = .busy
            }

            if let i = sessions.firstIndex(where: { $0.id == summary.id }) {
                sessions[i].directory = summary.directory.isEmpty ? sessions[i].directory : summary.directory
                if let t = summary.title, !t.isEmpty { sessions[i].title = t }
                if let m = summary.model { sessions[i].modelRef = Self.modelRef(forModel: m) }
                if let p = summary.lastPrompt { sessions[i].lastPrompt = p }
                if let r = summary.lastReply { sessions[i].lastReply = r }
                if sessions[i].phase != .errored { sessions[i].phase = phase }
                sessions[i].updatedAt = summary.updatedAt
            } else {
                sessions.append(AgentSession(
                    id: summary.id,
                    directory: summary.directory.isEmpty ? nil : summary.directory,
                    title: summary.title ?? "",
                    phase: phase,
                    source: .external,
                    lastPrompt: summary.lastPrompt,
                    lastReply: summary.lastReply,
                    lastTool: nil,
                    modelRef: summary.model.map { Self.modelRef(forModel: $0) },
                    updatedAt: summary.updatedAt))
            }
        }

        // Drop transcript-only sessions that disappeared from disk.
        let diskIDs = Set(summaries.map(\.id))
        sessions.removeAll { session in
            session.needsFirstPrompt ? false : (!diskIDs.contains(session.id) && runners[session.id] == nil)
        }

        sortSessions()

        // Safety net for queued prompts: the normal trigger is the bridge's
        // Stop event, but a Stop can get lost (app relaunch, dropped hook
        // POST). When the periodic scan sees an idle session that still has
        // a queue, drain it instead of letting the messages strand.
        for id in queuedPrompts.keys {
            guard let s = sessions.first(where: { $0.id == id }),
                  s.phase != .busy, s.phase != .waitingApproval, s.phase != .waitingAnswer,
                  runners[id] == nil else { continue }
            flushQueuedPrompt(for: id)
        }

        connected = !instances.isEmpty || !runners.isEmpty
    }

    private func sortSessions() {
        func rank(_ s: AgentSession) -> Int {
            switch s.phase {
            case .waitingApproval, .waitingAnswer: return 0
            case .busy: return 1
            case .errored: return 2
            case .idle: return 3
            }
        }
        sessions.sort { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.updatedAt > b.updatedAt
        }
    }

    // MARK: AgentBridgeDelegate

    func bridge(didRegisterInstance info: AgentInstanceInfo) {
        everConnected = true
        if !instances.contains(where: { $0.id == info.id }) {
            instances.append(info)
        }
        connected = true
    }

    func bridge(didReceiveEvent event: AgentEvent, sessionID: String) {
        everConnected = true
        connected = true

        switch event {
        case .sessionStarted(_, let directory):
            upsertSession(id: sessionID) { s in
                s.directory = directory ?? s.directory
                if s.phase == .errored { s.phase = .idle }
            }

        case .sessionEnded:
            // The session transcript persists; mark idle and refresh.
            upsertSession(id: sessionID) { s in
                if s.phase != .waitingApproval && s.phase != .waitingAnswer {
                    s.phase = .idle
                }
            }
            scheduleChatReload()

        case .promptSubmitted(_, let text):
            upsertSession(id: sessionID) { s in
                s.lastPrompt = text
                s.phase = .busy
            }
            scheduleChatReload()

        case .toolUsed(_, let tool, let detail):
            upsertSession(id: sessionID) { s in
                s.lastTool = tool
                if let d = detail, !d.isEmpty { s.lastReply = d }
            }

        case .stopped(_, let reply):
            var shouldNotify = false
            upsertSession(id: sessionID) { s in
                if s.phase == .busy { shouldNotify = true }
                s.phase = .idle
                if let reply, !reply.isEmpty { s.lastReply = reply }
            }
            if shouldNotify, Defaults[.aiAgentNotifyOnDone] {
                presentDoneCard(for: sessionID, reply: reply ?? "", attention: false)
            }
            scheduleChatReload()
            flushQueuedPrompt(for: sessionID)

        case .attention(_, let message):
            upsertSession(id: sessionID) { s in
                s.phase = .waitingApproval
            }
            if Defaults[.aiAgentNotifyOnDone] {
                presentDoneCard(for: sessionID, reply: message, attention: true)
            }

        case .errored(_, let message):
            upsertSession(id: sessionID) { s in
                s.phase = .errored
                s.lastReply = message
            }
        }
    }

    func bridge(didReceivePermission permission: AgentPendingPermission) {
        pendingPermissions.removeAll { $0.id == permission.id }
        pendingPermissions.append(permission)
        upsertSession(id: permission.sessionID) { s in
            s.phase = .waitingApproval
        }
        playArrivalSound(done: false)
    }

    func bridge(didReceiveQuestion question: AgentPendingQuestion) {
        pendingQuestions.removeAll { $0.id == question.id }
        pendingQuestions.append(question)
        upsertSession(id: question.sessionID) { s in
            s.phase = .waitingAnswer
        }
        playArrivalSound(done: false)
    }

    func bridgeDidExpire(requestID: String) {
        pendingPermissions.removeAll { $0.id == requestID }
        pendingQuestions.removeAll { $0.id == requestID }
        cardDismissedIDs.remove(requestID)
    }

    func bridgeStateSnapshot() -> AgentJSON {
        .object([
            "sessions": .array(sessions.map { s in
                .object([
                    "id": .string(s.id),
                    "project": .string(s.project),
                    "title": .string(s.displayTitle),
                    "phase": .string(String(describing: s.phase)),
                    "source": .string(String(describing: s.source)),
                    "model": .string(s.modelRef ?? ""),
                    "lastTool": .string(s.lastTool ?? ""),
                    "updatedAt": .number(s.updatedAt.timeIntervalSince1970),
                ])
            }),
            "pendingPermissions": .array(pendingPermissions.map { p in
                .object([
                    "id": .string(p.id),
                    "sessionID": .string(p.sessionID),
                    "tool": .string(p.tool),
                    "detail": .string(p.detail),
                ])
            }),
            "pendingQuestions": .array(pendingQuestions.map { q in
                .object([
                    "id": .string(q.id),
                    "sessionID": .string(q.sessionID),
                    "questions": .array(q.questions.map { .string($0.question) }),
                ])
            }),
            "instances": .number(Double(instances.count)),
            "runningRuns": .number(Double(runners.count)),
            "connected": .bool(connected),
            "claudeBinary": .string(claudeBinary),
            "needsAuth": .bool(needsAuth),
        ])
    }

    // MARK: Session store helpers

    private func upsertSession(id: String, mutate: (inout AgentSession) -> Void) {
        if let i = sessions.firstIndex(where: { $0.id == id }) {
            mutate(&sessions[i])
            sessions[i].updatedAt = Date()
        } else {
            var s = AgentSession(id: id, directory: nil, title: "")
            mutate(&s)
            s.updatedAt = Date()
            sessions.append(s)
        }
        sortSessions()
    }

    // MARK: Cards

    private func presentDoneCard(for sessionID: String, reply: String, attention: Bool) {
        // Dedupe: hooks (Stop) and the managed runner can both report completion.
        if doneCards.contains(where: { $0.sessionID == sessionID }) { return }
        let title = sessions.first { $0.id == sessionID }?.displayTitle ?? "Claude Code"
        let card = AgentDoneCard(
            sessionID: sessionID,
            title: attention ? "Claude needs you" : title,
            reply: attention ? "Attention: \(reply)" : reply,
            isAttention: attention)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            doneCards.append(card)
        }
        playArrivalSound(done: true)
        scheduleDoneCardCleanup()
    }

    private func scheduleDoneCardCleanup() {
        doneCardCleanupTask?.cancel()
        doneCardCleanupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.dismissOldestDoneCard()
        }
    }

    func dismissOldestDoneCard() {
        withAnimation(.easeOut(duration: 0.2)) {
            if !doneCards.isEmpty { doneCards.removeFirst() }
        }
    }

    func dismissCard(_ id: String) {
        cardDismissedIDs.insert(id)
        // A dismissed permission card falls through to Claude Code's normal
        // permission flow (the terminal prompt still works).
        bridge.fallThrough(requestID: id)
    }

    // MARK: Answering permissions / questions

    func approve(permission: AgentPendingPermission, always: Bool = false) {
        if always {
            // Same tool in this session skips future cards.
            bridge.allowAlways(sessionID: permission.sessionID, tool: permission.tool)
        }
        pendingPermissions.removeAll { $0.id == permission.id }
        cardDismissedIDs.remove(permission.id)
        bridge.respond(requestID: permission.id, decision: .allow)
        upsertSession(id: permission.sessionID) { s in
            if s.phase == .waitingApproval { s.phase = .busy }
        }
    }

    func deny(permission: AgentPendingPermission) {
        pendingPermissions.removeAll { $0.id == permission.id }
        cardDismissedIDs.remove(permission.id)
        bridge.respond(
            requestID: permission.id,
            decision: .deny(reason: "Denied from Boring Notch"))
        upsertSession(id: permission.sessionID) { s in
            if s.phase == .waitingApproval { s.phase = .idle }
        }
    }

    func answer(question: AgentPendingQuestion, answers: [[String]]) {
        pendingQuestions.removeAll { $0.id == question.id }
        cardDismissedIDs.remove(question.id)
        bridge.respond(requestID: question.id, decision: .answers(answers))
        upsertSession(id: question.sessionID) { s in
            if s.phase == .waitingAnswer { s.phase = .busy }
        }
    }

    // MARK: Chat

    func openChat(sessionID: String) {
        selectedSessionID = sessionID
        messages = []
        chatLoading = true
        Task {
            await loadMessages()
            chatLoading = false
        }
        // Refresh the session's model from its transcript.
        if let session = sessions.first(where: { $0.id == sessionID }) {
            let dir = session.directory
            Task {
                if let model = TranscriptStore.currentModel(sessionID: sessionID, directory: dir) {
                    await MainActor.run {
                        if let i = sessions.firstIndex(where: { $0.id == sessionID }) {
                            sessions[i].modelRef = Self.modelRef(forModel: model)
                        }
                    }
                }
            }
        }
    }

    func closeChat() {
        selectedSessionID = nil
        messages = []
    }

    private func scheduleChatReload() {
        guard selectedSessionID != nil else { return }
        reloadDebounce?.cancel()
        reloadDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.loadMessages()
        }
    }

    func loadMessages() async {
        guard let sessionID = selectedSessionID,
              let session = sessions.first(where: { $0.id == sessionID }) else { return }
        // Parsing a fresh transcript can mean reading megabytes — keep it off
        // the main thread.
        var parsed = await Task.detached(priority: .userInitiated) {
            TranscriptStore.messages(sessionID: sessionID, directory: session.directory)
        }.value
        // The queue lives outside the transcript, so re-render it after every
        // reload or it would flicker away on the next refresh.
        if let queue = queuedPrompts[sessionID], !queue.isEmpty {
            parsed += queue.enumerated().map { index, text in
                AgentChatMessage(id: "qmsg-\(index)-\(text)", role: .user, text: text)
            }
            parsed.append(AgentChatMessage(
                id: "qnote-\(queue.count)",
                role: .system,
                text: queue.count == 1
                    ? "1 message queued — sends when Claude finishes the current turn."
                    : "\(queue.count) messages queued — send when Claude finishes the current turn."))
        }
        if parsed != messages {
            messages = parsed
        }
        chatLoading = false
    }

    func sendPrompt(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let sessionID = selectedSessionID else { return }
        await performSend(text, sessionID: sessionID)
    }

    /// Sends one prompt into a specific session — whether it's the chat the
    /// user has open or a background session flushing its queue. Returns
    /// false when the send was refused (another send in flight), so callers
    /// can requeue instead of dropping the message.
    @discardableResult
    private func performSend(_ text: String, sessionID: String) async -> Bool {
        guard !text.isEmpty else { return false }
        guard !sending else { return false }
        guard runners[sessionID] == nil else { return false }

        let session = sessions.first { $0.id == sessionID }
        let directory = session?.directory
            ?? (Defaults[.aiAgentWorkspace].isEmpty ? NSHomeDirectory() : Defaults[.aiAgentWorkspace])

        // A session that is running in the user's terminal cannot accept a
        // headless resume — it would fork the conversation away from the
        // transcript the chat follows. Queue the message instead; the Stop
        // hook flushes it the moment the session goes idle.
        if session?.phase == .busy, runners[sessionID] == nil {
            queuePrompt(text, sessionID: sessionID)
            return true
        }

        // Echo the user's bubble right away — the transcript only gains the
        // matching entry once the run starts writing.
        if selectedSessionID == sessionID {
            messages.append(AgentChatMessage(
                id: "echo-\(UUID().uuidString)", role: .user, text: text))
        }

        // A notch-created session has no transcript yet: the first run
        // creates it with --session-id.
        let isNew = session?.needsFirstPrompt ?? (TranscriptStore.transcriptURL(for: sessionID, directory: directory) == nil)
        if let i = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[i].needsFirstPrompt = false
            sessions[i].lastPrompt = text
            sessions[i].phase = .busy
            sessions[i].source = .managed
        } else {
            var s = AgentSession(id: sessionID, directory: directory, title: "")
            s.lastPrompt = text
            s.phase = .busy
            s.source = .managed
            sessions.append(s)
            sortSessions()
        }

        sending = true
        defer { sending = false }

        let runner = ClaudeCodeRunner()
        runners[sessionID] = runner
        // Managed runs decide their tool approvals from the notch; the
        // bridge only holds requests for sessions marked here.
        bridge.markManaged(sessionID: sessionID)

        let model = runnerModelAlias(for: sessionID)
        await runner.run(
            prompt: text,
            sessionID: sessionID,
            isNewSession: isNew,
            directory: directory,
            model: model) { [weak self] event in
            guard let self else { return }
            switch event {
            case .assistantText:
                self.scheduleChatReload()
            case .toolUsed(let name, let detail):
                self.upsertSession(id: sessionID) { s in
                    s.lastTool = name
                    if let d = detail, !d.isEmpty { s.lastReply = d }
                }
                self.scheduleChatReload()
            case .finished(let reply, let isError, let message):
                self.runners[sessionID] = nil
                self.bridge.clearManaged(sessionID: sessionID)
                self.upsertSession(id: sessionID) { s in
                    s.phase = isError ? .errored : .idle
                    if isError, let message { s.lastReply = message }
                }
                self.scheduleChatReload()
                if isError, let message {
                    self.messages.append(AgentChatMessage(
                        id: "err-\(UUID().uuidString)", role: .error, text: "⚠️ \(message)"))
                } else if let reply, !reply.isEmpty, Defaults[.aiAgentNotifyOnDone] {
                    self.presentDoneCard(for: sessionID, reply: reply, attention: false)
                }
            }
        }
        await loadMessages()
        return true
    }

    // MARK: Queue persistence

    private func persistQueuedPrompts() {
        Defaults[.aiAgentQueuedPrompts] = (try? JSONEncoder().encode(queuedPrompts)) ?? Data()
    }

    private static func restoreQueuedPrompts() -> [String: [String]] {
        let data = Defaults[.aiAgentQueuedPrompts]
        guard !data.isEmpty,
              let map = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return map
    }

    /// Files a prompt to send once the busy session goes idle.
    private func queuePrompt(_ text: String, sessionID: String) {
        queuedPrompts[sessionID, default: []].append(text)
        if selectedSessionID == sessionID {
            messages.append(AgentChatMessage(
                id: "echo-\(UUID().uuidString)", role: .user, text: text))
            messages.append(AgentChatMessage(
                id: "queued-\(UUID().uuidString)",
                role: .system,
                text: "Queued — sends as soon as Claude finishes the current turn."))
        }
    }

    private func flushQueuedPrompt(for sessionID: String) {
        guard var queue = queuedPrompts[sessionID], !queue.isEmpty else { return }
        let next = queue.removeFirst()
        queuedPrompts[sessionID] = queue.isEmpty ? nil : queue
        Task { [weak self] in
            // Give the session's own .finished bookkeeping a beat to land,
            // then send. If another send is in flight, requeue for the next
            // idle instead of dropping the message.
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            if await !self.performSend(next, sessionID: sessionID) {
                self.queuedPrompts[sessionID, default: []].insert(next, at: 0)
            }
        }
    }

    func interrupt() {
        guard let sessionID = selectedSessionID else { return }
        runners[sessionID]?.interrupt()
        upsertSession(id: sessionID) { s in
            if s.phase == .busy { s.phase = .idle }
        }
    }

    func startNewSession() async {
        let id = UUID().uuidString
        let directory = Defaults[.aiAgentWorkspace].isEmpty ? NSHomeDirectory() : Defaults[.aiAgentWorkspace]
        var s = AgentSession(id: id, directory: directory, title: "")
        s.source = .managed
        s.needsFirstPrompt = true
        if !Defaults[.aiAgentModel].isEmpty {
            s.modelRef = Defaults[.aiAgentModel]
        }
        sessions.append(s)
        sortSessions()
        openChat(sessionID: id)
    }

    var isSessionRunning: Bool {
        guard let id = selectedSessionID else { return false }
        return runners[id] != nil
    }

    // MARK: Models

    /// The Claude Code model aliases, the models routed through the user's
    /// own provider setup, plus whatever they set as default in settings.json.
    private func loadModels() {
        var items: [AgentModel] = [
            AgentModel(id: "sonnet", providerID: "claude", name: "Sonnet"),
            AgentModel(id: "opus", providerID: "claude", name: "Opus"),
            AgentModel(id: "haiku", providerID: "claude", name: "Haiku"),
            AgentModel(id: "opusplan", providerID: "claude", name: "Opus Plan"),
            AgentModel(id: "glm-5.3-flash:cloud", providerID: "claude", name: "GLM 5.3 Flash (1M ctx)"),
            AgentModel(id: "glm-5.2:cloud", providerID: "claude", name: "GLM 5.2 (1M ctx)"),
            AgentModel(id: "minimax-m3:cloud", providerID: "claude", name: "MiniMax M3 (1M ctx)"),
            AgentModel(id: "gemma4:26b", providerID: "claude", name: "Gemma 4 26B (local)"),
        ]
        // The user's configured default model (settings.json "model").
        let settingsURL = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/settings.json")
        if let data = FileManager.default.contents(atPath: settingsURLPath),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let configured = obj["model"] as? String, !configured.isEmpty {
            if !items.contains(where: { $0.id == configured }) {
                items.append(AgentModel(id: configured, providerID: "claude", name: "Default (settings)"))
            }
        }
        availableModels = items
    }

    private var settingsURLPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/settings.json")
    }

    func switchModel(_ model: AgentModel) async {
        guard let sessionID = selectedSessionID else { return }
        if let i = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[i].modelRef = model.ref
        }
    }

    /// Maps a stored "claude/<alias>" ref to the value passed to `--model`.
    private func runnerModelAlias(for sessionID: String) -> String? {
        guard let session = sessions.first(where: { $0.id == sessionID }),
              let ref = session.modelRef, !ref.isEmpty else { return nil }
        let alias = ref.hasPrefix("claude/") ? String(ref.dropFirst("claude/".count)) : ref
        // Only pass models the CLI actually accepts. Transcripts record names
        // like "glm-5.3-flash" while the router only knows "glm-5.3-flash:cloud" —
        // an unrecognized alias 404s the whole run, so for anything outside the
        // known list send without --model and let the session keep its model.
        guard availableModels.contains(where: { $0.id == alias }) else { return nil }
        return alias
    }

    var selectedModel: AgentModel? {
        guard let session = selectedSession, let ref = session.modelRef else { return nil }
        return availableModels.first { $0.ref == ref }
    }

    /// Human-readable model name for a stored ref (e.g. transcript model ids).
    static func modelRef(forModel model: String) -> String {
        if model.contains("/") { return model }
        return "claude/\(model)"
    }
}