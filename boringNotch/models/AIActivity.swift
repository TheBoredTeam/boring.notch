import Foundation

// Shared with the XPC helper. Keep this file independent of UI and transport.
enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex, chatgpt, claude, claudeCode

    var id: String { rawValue }
    var name: String {
        switch self {
        case .codex: return "Codex"
        case .chatgpt: return "ChatGPT"
        case .claude: return "Claude"
        case .claudeCode: return "Claude Code"
        }
    }
    var bundleIdentifier: String {
        switch self {
        case .codex: return "com.openai.codex"
        case .chatgpt: return "com.openai.chat"
        case .claude, .claudeCode: return "com.anthropic.claudefordesktop"
        }
    }
    var supportsHooks: Bool { self == .codex || self == .claudeCode }
}

enum AIActivityStatus: String, Codable, CaseIterable, Sendable {
    case working, needsAttention, completed, unknown, idle, interrupted

    var label: String {
        switch self {
        case .working: return "Working"
        case .needsAttention: return "Needs attention"
        case .completed: return "Turn finished"
        case .unknown: return "Unconfirmed"
        case .idle: return "Idle"
        case .interrupted: return "Interrupted"
        }
    }
    var priority: Int {
        switch self {
        case .needsAttention: return 3
        case .working: return 2
        case .completed: return 1
        default: return 0
        }
    }
    // Index into the permanent red, yellow, green lamps. Nil dims all three.
    var illuminatedLamp: Int? {
        switch self {
        case .working: return 0
        case .needsAttention: return 1
        case .completed: return 2
        default: return nil
        }
    }
}

/// What a working session is doing right now, derived from the tool name only.
enum AIActivityAction: String, Codable, CaseIterable, Sendable {
    case thinking, reading, searching, editing, running, testing, browsing, delegating, usingTool

    func caption(_ detail: String?) -> String {
        switch self {
        case .thinking: return "Thinking"
        case .reading: return detail.map { "Reading \($0)" } ?? "Reading files"
        case .searching: return "Searching the code"
        case .editing: return detail.map { "Editing \($0)" } ?? "Editing files"
        case .running: return detail.map { "Running \($0)" } ?? "Running a command"
        case .testing: return "Running tests"
        case .browsing: return detail.map { "Browsing \($0)" } ?? "Searching the web"
        case .delegating: return detail.map { "Delegating to \($0)" } ?? "Delegating to an agent"
        case .usingTool: return detail.map { "Using \($0)" } ?? "Using a tool"
        }
    }
    var symbol: String {
        switch self {
        case .thinking: return "ellipsis.bubble"
        case .reading: return "book"
        case .searching: return "magnifyingglass"
        case .editing: return "pencil"
        case .running: return "terminal"
        case .testing: return "checkmark.seal"
        case .browsing: return "globe"
        case .delegating: return "person.2"
        case .usingTool: return "wrench.and.screwdriver"
        }
    }
}

enum AIActivitySource: String, Codable, Sendable {
    case hook, accessibility, preview
}

enum AIActivityEventKind: String, Codable, Sendable {
    case sessionStarted, started, activity, attention, resolved, stopped, completed
    case failed, interrupted, sessionEnded, subagentStarted, subagentStopped
}

struct AIActivityEvent: Codable, Sendable {
    var version = 1
    var id = UUID().uuidString
    var provider: AIProvider
    var sessionID: String
    var runID: String?
    var kind: AIActivityEventKind
    var timestamp = Date().timeIntervalSince1970
    var requestID: String?
    /// A permission request this result also settles; permission requests have no tool ID.
    var alsoResolves: String?
    var agentID: String?
    var project: String?
    var hostSessionID: String?
    /// The app that launched the runtime (Claude Desktop, a terminal, an editor): where you return to read the result.
    var hostBundleID: String?
    var isDesktop = true
    var reason: String?
    var hasBackgroundWork = false
    var action: AIActivityAction?
    /// A file basename, program name, web host or agent type; never arguments or content.
    var actionDetail: String?

    var isValid: Bool {
        version == 1 && !id.isEmpty && id.utf8.count <= 128
            && !sessionID.isEmpty && sessionID.utf8.count <= 256
            && (runID?.utf8.count ?? 0) <= 256
            && (requestID?.utf8.count ?? 0) <= 256
            && (alsoResolves?.utf8.count ?? 0) <= 256
            && (agentID?.utf8.count ?? 0) <= 256
            && (reason?.utf8.count ?? 0) <= 512
            && (project?.utf8.count ?? 0) <= 256
            && (hostSessionID?.utf8.count ?? 0) <= 128
            && (hostBundleID?.utf8.count ?? 0) <= 128
            && (actionDetail?.utf8.count ?? 0) <= 256
            && timestamp.isFinite
    }
}

struct AIActivitySession: Codable, Identifiable, Equatable, Sendable {
    var provider: AIProvider
    var sessionID: String
    var runID: String?
    var status: AIActivityStatus = .idle
    var source: AIActivitySource = .hook
    var project: String = ""
    var reason: String = "Waiting for a new turn"
    var hostSessionID: String?
    var hostBundleID: String?
    var isDesktop = true
    var updatedAt = Date()
    var lastEventAt: Date?
    var pendingRequests: [String: String] = [:]
    var activeAgents: Set<String> = []
    var completionCandidateAt: Date?
    var completedAt: Date?
    /// When you were first back in the host app after completion; green yields shortly after.
    var acknowledgedAt: Date?
    var rootResponseStopped = false
    var action: AIActivityAction?
    var actionDetail: String?

    var id: String { "\(source.rawValue):\(provider.rawValue):\(sessionID)" }
    var title: String { project.isEmpty ? provider.name : project }
    var returnBundleID: String { hostBundleID ?? provider.bundleIdentifier }
    /// Caption for a working session; other states keep their reason.
    var caption: String? { status == .working ? action?.caption(actionDetail) : nil }

    static let acknowledgementDelay: TimeInterval = 3

    func appearsInNotch(at now: Date) -> Bool {
        switch status {
        case .working, .needsAttention: return true
        case .completed:
            // Green waits for you to return to the app, rather than expiring while you are away.
            guard completedAt != nil else { return false }
            return acknowledgedAt.map { now.timeIntervalSince($0) < Self.acknowledgementDelay } ?? true
        default: return false
        }
    }

    /// Yellow grows the closed notch downward until you go to the app that is waiting.
    func showsAttentionBanner(at now: Date) -> Bool {
        status == .needsAttention && (acknowledgedAt.map { now.timeIntervalSince($0) < Self.acknowledgementDelay } ?? true)
    }

    static func preferred(_ sessions: [Self], at now: Date) -> Self? {
        grouped(sessions, at: now).first?.lead
    }

    /// One companion per provider, most urgent first. Each group leads with its most urgent session.
    static func grouped(_ sessions: [Self], at now: Date) -> [AIActivityGroup] {
        let ordered = sessions.filter { $0.appearsInNotch(at: now) }.sorted {
            if $0.status.priority != $1.status.priority { return $0.status.priority > $1.status.priority }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
        var groups: [AIActivityGroup] = []
        for session in ordered {
            if let index = groups.firstIndex(where: { $0.provider == session.provider }) {
                groups[index].count += 1
            } else {
                groups.append(AIActivityGroup(lead: session))
            }
        }
        return groups
    }
}

struct AIActivityGroup: Identifiable, Equatable, Sendable {
    var lead: AIActivitySession
    /// Visible sessions from this provider, including the lead.
    var count = 1
    var provider: AIProvider { lead.provider }
    var id: String { provider.rawValue }
}

enum AIHookConnectionState: String, Codable, Sendable {
    // needsReconnect: our hooks exist but are incomplete or run another copy of the helper.
    case notConnected, connected, needsReconnect
}

struct AIHookConnection: Codable, Equatable, Sendable {
    var state: AIHookConnectionState = .notConnected
    /// Helper executable the installed hooks run, when any are installed.
    var executablePath: String?
}

struct AIActivitySnapshot: Codable, Sendable {
    var sessions: [AIActivitySession] = []
    var hookConnections: [String: AIHookConnection] = [:]
    var accessibilityAuthorized = false
    var desktopObservationEnabled = false
    var bridgeReady = false
    var message: String?
}

/// Deterministic reducer: no file reads, wall-clock timers, UI or approval decisions.
struct AIActivityStore {
    private(set) var sessions: [String: AIActivitySession] = [:]
    private var seenIDs: Set<String> = []
    private var recentIDs: [String] = []

    mutating func apply(_ event: AIActivityEvent, receivedAt now: Date = Date()) {
        guard event.isValid, abs(event.timestamp - now.timeIntervalSince1970) < 300,
              !seenIDs.contains(event.id) else { return }
        seenIDs.insert(event.id)
        recentIDs.append(event.id)
        if recentIDs.count > 1024 { seenIDs.remove(recentIDs.removeFirst()) }

        let key = "hook:\(event.provider.rawValue):\(event.sessionID)"
        let eventDate = Date(timeIntervalSince1970: event.timestamp)
        var session = sessions[key] ?? AIActivitySession(provider: event.provider, sessionID: event.sessionID)
        guard eventDate >= (session.lastEventAt ?? .distantPast) else { return }
        let newTurn = event.kind == .started || event.kind == .sessionStarted
        if !newTurn, let runID = event.runID, let current = session.runID, runID != current { return }
        session.updatedAt = eventDate
        session.lastEventAt = eventDate
        session.project = event.project ?? session.project
        session.hostSessionID = event.hostSessionID ?? session.hostSessionID
        session.hostBundleID = event.hostBundleID ?? session.hostBundleID
        session.isDesktop = event.isDesktop

        switch event.kind {
        case .sessionStarted:
            session.runID = event.runID
            session.status = .idle
            session.reason = "Connected; waiting for a new turn"
            session.pendingRequests = [:]
            session.activeAgents = []
            session.completionCandidateAt = nil
            session.completedAt = nil
            session.acknowledgedAt = nil
            session.rootResponseStopped = false
        case .started:
            // A queued/steered prompt can belong to the same running turn.
            if event.runID == nil || event.runID != session.runID {
                session.pendingRequests = [:]
                session.activeAgents = []
            }
            session.runID = event.runID ?? UUID().uuidString
            session.status = session.pendingRequests.isEmpty ? .working : .needsAttention
            session.reason = session.pendingRequests.values.sorted().first ?? "Working on this turn"
            session.completionCandidateAt = nil
            session.completedAt = nil
            session.acknowledgedAt = nil
            session.rootResponseStopped = false
            session.action = .thinking
            session.actionDetail = nil
        case .activity:
            session.completionCandidateAt = nil
            session.completedAt = nil
            session.rootResponseStopped = false
            session.action = event.action ?? .usingTool
            session.actionDetail = event.actionDetail
            session.status = session.pendingRequests.isEmpty ? .working : .needsAttention
            session.reason = session.pendingRequests.values.sorted().first ?? "Working on this turn"
        case .attention, .failed:
            let reason = event.reason ?? (event.kind == .failed ? "The turn needs your attention" : "Waiting for your response")
            session.pendingRequests[event.requestID ?? "turn"] = reason
            // A new question drops the banner again, even after you looked at an earlier one.
            session.acknowledgedAt = nil
            session.status = .needsAttention
            session.reason = reason
            session.completionCandidateAt = nil
            session.completedAt = nil
        case .resolved:
            // Never clear another outstanding question on an unrelated tool's result.
            if let requestID = event.requestID { session.pendingRequests.removeValue(forKey: requestID) }
            if let permission = event.alsoResolves { session.pendingRequests.removeValue(forKey: permission) }
            // Between tools the model is reasoning about the result.
            session.action = .thinking
            session.actionDetail = nil
            session.status = session.pendingRequests.isEmpty ? .working : .needsAttention
            session.reason = session.pendingRequests.values.sorted().first ?? "Working on this turn"
            session.completionCandidateAt = nil
            session.completedAt = nil
            session.rootResponseStopped = false
        case .subagentStarted:
            if let agentID = event.agentID { session.activeAgents.insert(agentID) }
            if session.action != .delegating { session.action = .delegating; session.actionDetail = nil }
            session.status = session.pendingRequests.isEmpty ? .working : .needsAttention
            session.reason = session.pendingRequests.values.sorted().first ?? "Background work is running"
            session.completionCandidateAt = nil
        case .subagentStopped:
            if let agentID = event.agentID { session.activeAgents.remove(agentID) }
            // A child finishing must never finish its parent's turn.
            // When a parent has already stopped, a child ending only invalidates
            // the old busy indication; require fresh parent evidence for green.
            if session.rootResponseStopped && session.activeAgents.isEmpty && session.pendingRequests.isEmpty {
                session.status = .unknown
                session.reason = "Background work ended; waiting for a parent update"
            }
        case .stopped:
            session.rootResponseStopped = true
            // A finished response cannot still be waiting on a permission dialog: a manual denial
            // sends no hook of its own. Questions such as async ones can legitimately outlive it.
            session.pendingRequests = session.pendingRequests.filter { !$0.key.hasPrefix("permission:") }
            if !session.pendingRequests.isEmpty {
                session.status = .needsAttention
                session.reason = session.pendingRequests.values.sorted().first ?? "Waiting for your response"
            } else if !session.activeAgents.isEmpty || event.hasBackgroundWork {
                session.status = .working
                session.reason = "Background work is still running"
            } else {
                session.status = .unknown
                session.reason = "Response ended; checking for continuation"
                session.completionCandidateAt = now.addingTimeInterval(1.5)
            }
        case .completed:
            guard session.pendingRequests.isEmpty, session.activeAgents.isEmpty, !event.hasBackgroundWork else { break }
            session.status = .completed
            session.reason = "This turn finished; review the result in the app"
            session.completedAt = now
            session.acknowledgedAt = nil
            session.completionCandidateAt = nil
        case .interrupted, .sessionEnded:
            session.status = event.kind == .interrupted ? .interrupted : .unknown
            session.reason = event.kind == .interrupted ? "You interrupted this turn" : "Session ended"
            session.pendingRequests = [:]
            session.activeAgents = []
            session.completionCandidateAt = nil
            session.completedAt = nil
            session.rootResponseStopped = false
        }
        if session.status != .working { session.action = nil; session.actionDetail = nil }
        sessions[key] = session
        if sessions.count > 100, let oldest = sessions.values.filter({ $0.status.priority == 0 }).min(by: { $0.updatedAt < $1.updatedAt }) {
            sessions.removeValue(forKey: oldest.id)
        }
    }

    // A killed runtime or lost SessionEnd never sends a final hook. Long tools are silent too,
    // so these limits are deliberately generous and only dim the lamps; they never turn green.
    static let workingStaleInterval: TimeInterval = 30 * 60
    static let attentionStaleInterval: TimeInterval = 8 * 60 * 60

    mutating func advance(to now: Date) {
        for key in Array(sessions.keys) {
            guard var session = sessions[key], session.completionCandidateAt == nil,
                  let lastEvent = session.lastEventAt else { continue }
            let limit = session.status == .working ? Self.workingStaleInterval
                : session.status == .needsAttention ? Self.attentionStaleInterval : nil
            guard let limit, now.timeIntervalSince(lastEvent) >= limit else { continue }
            session.status = .unknown
            session.reason = "No updates for a while; work state is unconfirmed"
            session.pendingRequests = [:]
            session.activeAgents = []
            session.updatedAt = now
            sessions[key] = session
        }
        for key in Array(sessions.keys) {
            guard var session = sessions[key], let deadline = session.completionCandidateAt, deadline <= now else { continue }
            session.completionCandidateAt = nil
            if session.pendingRequests.isEmpty && session.activeAgents.isEmpty {
                session.status = .completed
                session.reason = "This response finished; review the result in the app"
                session.completedAt = now
                session.acknowledgedAt = nil
                session.updatedAt = now
            }
            sessions[key] = session
        }
    }

    /// Being in the host app after a response finished, or while it waits for you, means you have seen it.
    mutating func observeFrontmost(_ bundleID: String?, at now: Date) {
        guard let bundleID else { return }
        for key in Array(sessions.keys) {
            guard var session = sessions[key], session.status == .completed || session.status == .needsAttention,
                  session.acknowledgedAt == nil,
                  session.returnBundleID == bundleID else { continue }
            session.acknowledgedAt = now
            sessions[key] = session
        }
    }

    mutating func dismiss(_ id: String) {
        // Acknowledging a row never resolves a live approval or question.
        guard let session = sessions[id], session.status.priority < 2 else { return }
        sessions.removeValue(forKey: id)
    }

    mutating func disconnect(_ provider: AIProvider) {
        sessions = sessions.filter { $0.value.provider != provider }
    }

    mutating func markDesktopUnavailable(_ provider: AIProvider, at now: Date) {
        for key in Array(sessions.keys) {
            guard var session = sessions[key], session.provider == provider, session.isDesktop,
                  session.status.priority >= 2 || session.completionCandidateAt != nil else { continue }
            session.status = .unknown
            session.reason = "App closed; work state is unconfirmed"
            session.completionCandidateAt = nil
            session.completedAt = nil
            session.updatedAt = now
            sessions[key] = session
        }
    }
}
