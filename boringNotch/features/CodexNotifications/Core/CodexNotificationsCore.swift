import Foundation

public enum PriorityResolver {
    public static func select<Candidate>(
        from candidates: [Candidate],
        isVisible: (Candidate) -> Bool,
        priority: (Candidate) -> Int,
        updatedAt: (Candidate) -> Date
    ) -> Candidate? {
        candidates.reduce(nil) { selected, candidate in
            guard isVisible(candidate) else { return selected }
            guard let selected else { return candidate }

            let candidatePriority = priority(candidate)
            let selectedPriority = priority(selected)
            if candidatePriority != selectedPriority {
                return candidatePriority > selectedPriority ? candidate : selected
            }
            return updatedAt(candidate) > updatedAt(selected) ? candidate : selected
        }
    }
}

public enum CodexNotificationTiming {
    public static let transitionAnimationResponse: TimeInterval = 0.42
    public static let passiveDwellDuration: TimeInterval = 3
    public static let codexHoverExpansionDelay: TimeInterval = 0.6

    public static func transitionDuration(
        animationSpeedMultiplier: Double,
        animationsEnabled: Bool
    ) -> TimeInterval {
        guard animationsEnabled else { return 0 }
        let speed = max(animationSpeedMultiplier, 0.01)
        return transitionAnimationResponse / speed
    }
}

public enum CodexApplicationRoute {
    public static let officialBundleIdentifier = "com.openai.codex"
    public static let settingsURL = URL(string: "codex://settings")!

    public static func threadURL(sessionID: String) -> URL? {
        guard !sessionID.isEmpty else { return nil }
        let allowedCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        guard let encodedSessionID = sessionID.addingPercentEncoding(
            withAllowedCharacters: allowedCharacters
        ) else {
            return nil
        }
        return URL(string: "codex://threads/\(encodedSessionID)")
    }
}

public enum CodexApplicationLaunchError: LocalizedError, Equatable {
    case applicationUnavailable

    public var errorDescription: String? {
        switch self {
        case .applicationUnavailable:
            "The official Codex app could not be found. Install or reopen Codex, then try again."
        }
    }
}

@MainActor
public protocol CodexApplicationWorkspace: AnyObject {
    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL?
    func open(_ url: URL?, withApplicationAt applicationURL: URL) async throws
}

@MainActor
public struct CodexApplicationLauncher {
    private let workspace: any CodexApplicationWorkspace

    public init(workspace: any CodexApplicationWorkspace) {
        self.workspace = workspace
    }

    public func open(_ url: URL?) async throws {
        guard let applicationURL = workspace.urlForApplication(
            withBundleIdentifier: CodexApplicationRoute.officialBundleIdentifier
        ) else {
            throw CodexApplicationLaunchError.applicationUnavailable
        }
        try await workspace.open(url, withApplicationAt: applicationURL)
    }
}

@MainActor
public enum CodexPermissionReviewHandoff {
    public static func perform(
        openCodex: () async throws -> Void,
        handOffPermission: () async throws -> Void
    ) async throws {
        try await openCodex()
        try await handOffPermission()
    }
}

public enum CodexClosedActivityTapRouting: Equatable, Sendable {
    case expandNotch
    case openCodex

    public init(status: CodexJobStatus) {
        if status == .permissionRequired {
            self = .expandNotch
        } else {
            self = .openCodex
        }
    }
}

public struct CodexClosedActivityAccessibility: Equatable, Sendable {
    public let value: String
    public let hint: String

    public init(
        status: CodexJobStatus,
        projectName: String,
        launchError: String? = nil
    ) {
        if status == .permissionRequired {
            value = "Permission required."
            hint = "Activate to review this permission in Boring Notch."
        } else if let launchError {
            value = launchError
            hint = "Activate to retry opening this task in Codex."
        } else {
            value = "\(status.title). \(projectName)"
            hint = "Activate to open this task in Codex."
        }
    }
}

public struct CodexNotificationPresentationToken: Hashable, Sendable {
    public let id: String
    public let createdAt: Date

    public init(_ notification: CodexJobNotification) {
        id = notification.id
        createdAt = notification.createdAt
    }

    public func matches(_ notification: CodexJobNotification) -> Bool {
        id == notification.id && createdAt == notification.createdAt
    }
}

public struct CodexPassivePresentationPolicy: Equatable, Sendable {
    private enum CompactLaunch: Equatable, Sendable {
        case opening
        case failed(String)
    }

    private var compactLaunches = [CodexNotificationPresentationToken: CompactLaunch]()

    public init() {}

    public mutating func consumeBeforeFade(
        _ token: CodexNotificationPresentationToken,
        from state: inout CodexNotificationState
    ) {
        state.dismiss(token)
        discardCompactLaunch(for: token)
    }

    public mutating func beginCompactLaunch(
        for token: CodexNotificationPresentationToken
    ) -> Bool {
        if compactLaunches[token] == .opening {
            return false
        }
        compactLaunches[token] = .opening
        return true
    }

    public mutating func recordCompactLaunchFailure(
        _ message: String,
        for token: CodexNotificationPresentationToken
    ) {
        guard compactLaunches[token] == .opening else { return }
        compactLaunches[token] = .failed(message)
    }

    public mutating func recordCompactLaunchSuccess(
        for token: CodexNotificationPresentationToken
    ) {
        discardCompactLaunch(for: token)
    }

    public func preventsAutomaticDismissal(
        of token: CodexNotificationPresentationToken
    ) -> Bool {
        compactLaunches[token] != nil
    }

    public func compactLaunchError(
        for token: CodexNotificationPresentationToken
    ) -> String? {
        guard case .failed(let message) = compactLaunches[token] else { return nil }
        return message
    }

    func shouldCancelPassiveDismissalTask(
        for token: CodexNotificationPresentationToken,
        activePresentationToken: CodexNotificationPresentationToken?
    ) -> Bool {
        preventsAutomaticDismissal(of: token)
            && activePresentationToken == token
    }

    public mutating func discardCompactLaunch(
        for token: CodexNotificationPresentationToken
    ) {
        compactLaunches[token] = nil
    }

    public mutating func reset() {
        compactLaunches.removeAll()
    }
}

public struct CodexNotificationReplayGuard: Sendable {
    private let lifetime: TimeInterval
    private var acceptedPayloads = [String: Date]()

    public init(lifetime: TimeInterval) {
        self.lifetime = lifetime
    }

    public mutating func accept(_ payload: String, now: Date = Date()) -> Bool {
        acceptedPayloads = acceptedPayloads.filter {
            now.timeIntervalSince($0.value) <= lifetime
        }
        guard acceptedPayloads[payload] == nil else { return false }
        acceptedPayloads[payload] = now
        return true
    }
}

public struct CodexNotificationPresentationSurfaces: Equatable, Sendable {
    private(set) var activeSurfaceIDs: Set<String> = []
    private(set) var hoveredSurfaceIDs: Set<String> = []

    public init() {}

    public var isPassiveDismissalPaused: Bool {
        !hoveredSurfaceIDs.isEmpty
    }

    public mutating func begin(surfaceID: String) {
        activeSurfaceIDs.insert(surfaceID)
    }

    public mutating func end(surfaceID: String) {
        activeSurfaceIDs.remove(surfaceID)
        hoveredSurfaceIDs.remove(surfaceID)
    }

    public mutating func setHovered(_ isHovered: Bool, surfaceID: String) {
        if isHovered {
            activeSurfaceIDs.insert(surfaceID)
            hoveredSurfaceIDs.insert(surfaceID)
        } else {
            hoveredSurfaceIDs.remove(surfaceID)
        }
    }

    public mutating func reset() {
        activeSurfaceIDs.removeAll()
        hoveredSurfaceIDs.removeAll()
    }
}

public struct CodexPermissionCallback: Equatable, Sendable {
    public let port: Int
    public let token: String
    public let expiresAt: Date

    public init(port: Int, token: String, expiresAt: Date) {
        self.port = port
        self.token = token
        self.expiresAt = expiresAt
    }

    public func isActive(at date: Date = Date()) -> Bool {
        expiresAt > date
    }
}

public enum CodexPermissionDecision: String, Equatable, Sendable {
    case allow
    case deny
    case reviewInCodex = "codex"
}

public struct CodexPermissionDetails: Equatable, Sendable {
    public let toolName: String
    public let description: String?
    public let command: String?
    public let rawCommand: String?
    public let additionalInput: String?
    public let isAutoReviewed: Bool

    public init(
        toolName: String,
        description: String? = nil,
        command: String? = nil,
        rawCommand: String? = nil,
        additionalInput: String? = nil,
        isAutoReviewed: Bool = false
    ) {
        self.toolName = toolName
        self.description = description
        self.command = command
        self.rawCommand = rawCommand
        self.additionalInput = additionalInput
        self.isAutoReviewed = isAutoReviewed
    }

    public var summary: String {
        description
            ?? command
            ?? additionalInput
            ?? "Codex needs permission to use \(toolName)."
    }

}

public enum CodexJobStatus: Equatable, Sendable {
    case permissionRequired
    case responseReady
    case update
    case stopped

    public var priority: Int {
        self == .permissionRequired ? 4 : 2
    }

    public var isPersistent: Bool { self == .permissionRequired }

    public var title: String {
        switch self {
        case .permissionRequired: "Permission Required"
        case .responseReady: "Response ready"
        case .update: "Codex update"
        case .stopped: "Stopped"
        }
    }

    public var icon: String {
        switch self {
        case .permissionRequired: "lock.shield.fill"
        case .responseReady: "text.bubble.fill"
        case .update: "info.circle.fill"
        case .stopped: "stop.circle.fill"
        }
    }

    public var nextAction: String { "Open Codex" }
}

public struct CodexJobNotification: Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionID: String
    public let turnID: String?
    public let requestID: String?
    public let chatTitle: String
    public let jobTitle: String
    public let userPrompt: String
    public let projectName: String
    public let resultSummary: String
    public let status: CodexJobStatus
    public let permissionCallback: CodexPermissionCallback?
    public let permissionDetails: CodexPermissionDetails?
    public let createdAt: Date

    public init(
        id: String,
        sessionID: String,
        turnID: String?,
        requestID: String?,
        jobTitle: String,
        resultSummary: String,
        chatTitle: String? = nil,
        userPrompt: String? = nil,
        projectName: String = "Codex",
        status: CodexJobStatus,
        permissionCallback: CodexPermissionCallback? = nil,
        permissionDetails: CodexPermissionDetails? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.turnID = turnID
        self.requestID = requestID
        self.chatTitle = chatTitle ?? jobTitle
        self.jobTitle = jobTitle
        self.userPrompt = userPrompt ?? jobTitle
        self.projectName = projectName
        self.resultSummary = resultSummary
        self.status = status
        self.permissionCallback = permissionCallback
        self.permissionDetails = permissionDetails
        self.createdAt = createdAt
    }
}

public enum CodexHookEvent: Equatable, Sendable {
    case userPrompt(
        sessionID: String,
        turnID: String?,
        cwd: String?,
        prompt: String,
        chatTitle: String? = nil,
        projectName: String? = nil
    )
    case permissionRequest(
        sessionID: String,
        turnID: String?,
        requestID: String,
        cwd: String?,
        details: CodexPermissionDetails,
        callback: CodexPermissionCallback? = nil,
        chatTitle: String? = nil,
        projectName: String? = nil
    )
    case stop(
        sessionID: String,
        turnID: String?,
        cwd: String?,
        result: String?,
        chatTitle: String? = nil,
        projectName: String? = nil
    )
    case interrupt(
        sessionID: String,
        turnID: String,
        cwd: String?,
        chatTitle: String? = nil,
        projectName: String? = nil
    )
}

public enum CodexHookEventParserError: Error, Equatable {
    case invalidJSON
    case missingField(String)
    case unsupportedEvent(String)
    case payloadTooLarge
}

extension CodexHookEventParserError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidJSON: "Codex sent an invalid hook payload"
        case .missingField(let field): "The Codex hook payload is missing \(field)"
        case .unsupportedEvent(let event): "The Codex hook event \(event) is not supported"
        case .payloadTooLarge: "The Codex hook payload is too large"
        }
    }
}

public enum CodexHookEventParser {
    public static let maximumPayloadBytes = 256 * 1024

    public static func parse(_ string: String) throws -> CodexHookEvent {
        try parse(Data(string.utf8))
    }

    public static func parse(_ data: Data) throws -> CodexHookEvent {
        guard data.count <= maximumPayloadBytes else {
            throw CodexHookEventParserError.payloadTooLarge
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexHookEventParserError.invalidJSON
        }
        guard let eventName = object["hook_event_name"] as? String else {
            throw CodexHookEventParserError.missingField("hook_event_name")
        }
        guard let sessionID = object["session_id"] as? String, !sessionID.isEmpty else {
            throw CodexHookEventParserError.missingField("session_id")
        }

        let turnID = nonemptyString(object["turn_id"])
        let cwd = nonemptyString(object["cwd"])
        let chatTitle = nonemptyString(object["chat_title"])
        let projectName = nonemptyString(object["project_name"])

        switch eventName {
        case "UserPromptSubmit":
            guard let prompt = nonemptyString(object["prompt"]) else {
                throw CodexHookEventParserError.missingField("prompt")
            }
            return .userPrompt(
                sessionID: sessionID,
                turnID: turnID,
                cwd: cwd,
                prompt: prompt,
                chatTitle: chatTitle,
                projectName: projectName
            )

        case "PermissionRequest":
            guard let requestID = authenticatedRequestID(from: object) else {
                throw CodexHookEventParserError.missingField("boring_notch_auth.nonce")
            }
            let toolName = nonemptyString(object["tool_name"]) ?? "Codex"
            return .permissionRequest(
                sessionID: sessionID,
                turnID: turnID,
                requestID: requestID,
                cwd: cwd,
                details: permissionDetails(from: object, toolName: toolName),
                callback: permissionCallback(from: object),
                chatTitle: chatTitle,
                projectName: projectName
            )

        case "Stop":
            return .stop(
                sessionID: sessionID,
                turnID: turnID,
                cwd: cwd,
                result: nonemptyString(object["last_assistant_message"]),
                chatTitle: chatTitle,
                projectName: projectName
            )

        case "Interrupt":
            guard let turnID else {
                throw CodexHookEventParserError.missingField("turn_id")
            }
            return .interrupt(
                sessionID: sessionID,
                turnID: turnID,
                cwd: cwd,
                chatTitle: chatTitle,
                projectName: projectName
            )

        default:
            throw CodexHookEventParserError.unsupportedEvent(eventName)
        }
    }

    private static func permissionDetails(
        from object: [String: Any],
        toolName: String
    ) -> CodexPermissionDetails {
        let isAutoReviewed = nonemptyString(
            object["boring_notch_approval_reviewer"]
        ) == "auto_review"
        guard let input = object["tool_input"] as? [String: Any] else {
            return CodexPermissionDetails(
                toolName: toolName,
                isAutoReviewed: isAutoReviewed
            )
        }

        let description = nonemptyString(input["description"])
        let rawCommand = nonemptyString(input["command"])
        let command = toolName == "apply_patch"
            ? applyPatchTargets(from: rawCommand) ?? rawCommand
            : rawCommand
        let remainingInput = input.filter {
            !["description", "command"].contains($0.key)
        }
        var additionalInput: String?
        if !remainingInput.isEmpty,
           JSONSerialization.isValidJSONObject(remainingInput),
           let data = try? JSONSerialization.data(
               withJSONObject: remainingInput,
               options: [.prettyPrinted, .sortedKeys]
           ),
           let json = String(data: data, encoding: .utf8) {
            additionalInput = json
        }

        return CodexPermissionDetails(
            toolName: toolName,
            description: description,
            command: command,
            rawCommand: command == rawCommand ? nil : rawCommand,
            additionalInput: additionalInput,
            isAutoReviewed: isAutoReviewed
        )
    }

    private static func permissionCallback(
        from object: [String: Any]
    ) -> CodexPermissionCallback? {
        guard let approval = object["boring_notch_approval"] as? [String: Any],
              let port = approval["port"] as? Int,
              (1024...65535).contains(port),
              let token = approval["token"] as? String,
              token.count >= 32,
              token.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII && (
                      CharacterSet.alphanumerics.contains(scalar)
                          || scalar == "_"
                          || scalar == "-"
                  )
              }),
              let expiresAt = approval["expires_at"] as? TimeInterval,
              expiresAt.isFinite,
              expiresAt > 0 else {
            return nil
        }
        return CodexPermissionCallback(
            port: port,
            token: token,
            expiresAt: Date(timeIntervalSince1970: expiresAt)
        )
    }

    private static func authenticatedRequestID(
        from object: [String: Any]
    ) -> String? {
        guard let auth = object["boring_notch_auth"] as? [String: Any],
              let nonce = nonemptyString(auth["nonce"]),
              nonce.utf8.count == 32,
              nonce.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII
                      && CharacterSet(charactersIn: "0123456789abcdef").contains(scalar)
              }) else {
            return nil
        }
        return nonce
    }

    private static func applyPatchTargets(from command: String?) -> String? {
        guard let command else { return nil }
        let prefixes = ["*** Add File: ", "*** Update File: ", "*** Delete File: "]
        var targets: [String] = []

        for line in command.components(separatedBy: .newlines) {
            guard let prefix = prefixes.first(where: line.hasPrefix) else { continue }
            let target = line.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !target.isEmpty, !targets.contains(target) {
                targets.append(target)
            }
        }
        return targets.isEmpty ? nil : targets.joined(separator: "\n")
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

public struct CodexNotificationState: Equatable, Sendable {
    public private(set) var notifications: [CodexJobNotification]

    // Retained after dismissal so duplicate/delayed delivery cannot resurface a turn.
    private var terminalStatuses: [String: CodexJobStatus] = [:]
    private var recentTerminalIDs: [String] = []
    private var latestJobBySession: [String: JobContext]
    private var recentJobSessionIDs: [String]
    private let maximumNotifications = 20
    private let maximumJobContexts = 20

    public init(notifications: [CodexJobNotification] = []) {
        self.notifications = notifications
        latestJobBySession = [:]
        recentJobSessionIDs = []
    }

    public mutating func reduce(_ event: CodexHookEvent, at date: Date = Date()) {
        switch event {
        case .userPrompt(
            let sessionID,
            let turnID,
            let cwd,
            let prompt,
            let chatTitle,
            let projectName
        ):
            notifications.removeAll {
                $0.sessionID == sessionID && !$0.status.isPersistent
            }
            let resumedID = Self.correlationID(sessionID: sessionID, turnID: turnID, requestID: nil)
            if terminalStatuses[resumedID] != .stopped {
                terminalStatuses.removeValue(forKey: resumedID)
                recentTerminalIDs.removeAll { $0 == resumedID }
            }
            let userInstruction = CodexText.userInstruction(from: prompt)
            storeJobContext(JobContext(
                turnID: turnID,
                cwd: cwd,
                prompt: userInstruction,
                title: CodexText.short(userInstruction, limit: 84),
                chatTitle: chatTitle
                    ?? CodexText.short(userInstruction, limit: 84),
                projectName: projectName ?? Self.projectName(cwd: cwd)
            ), for: sessionID)

        case .permissionRequest(
            let sessionID,
            let turnID,
            let requestID,
            let cwd,
            let details,
            let callback,
            let chatTitle,
            let projectName
        ):
            let terminalID = Self.correlationID(sessionID: sessionID, turnID: turnID, requestID: nil)
            guard !details.isAutoReviewed, terminalStatuses[terminalID] == nil else { return }
            let notification = makeNotification(
                sessionID: sessionID,
                turnID: turnID,
                requestID: requestID,
                cwd: cwd,
                result: details.summary,
                status: .permissionRequired,
                permissionCallback: callback,
                permissionDetails: details,
                chatTitle: chatTitle,
                projectName: projectName,
                date: date
            )
            upsert(notification)

        case .stop(
            let sessionID,
            let turnID,
            let cwd,
            let result,
            let chatTitle,
            let projectName
        ):
            let terminalID = Self.correlationID(sessionID: sessionID, turnID: turnID, requestID: nil)
            guard turnID == nil || terminalStatuses[terminalID] == nil else { return }
            notifications.removeAll { notification in
                guard notification.status == .permissionRequired,
                      notification.sessionID == sessionID else {
                    return false
                }
                return notification.turnID == turnID
            }
            let message = result?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasResponse = message?.isEmpty == false
            let status: CodexJobStatus = hasResponse ? .responseReady : .update
            if turnID != nil { rememberTerminal(status, id: terminalID) }
            let notification = makeNotification(
                sessionID: sessionID,
                turnID: turnID,
                requestID: nil,
                cwd: cwd,
                result: hasResponse ? (message ?? "") : "Response details unavailable. Open Codex to review.",
                status: status,
                chatTitle: chatTitle,
                projectName: projectName,
                date: date
            )
            upsert(notification)

        case .interrupt(let sessionID, let turnID, let cwd, let chatTitle, let projectName):
            let terminalID = Self.correlationID(sessionID: sessionID, turnID: turnID, requestID: nil)
            guard terminalStatuses[terminalID] != .stopped else { return }
            rememberTerminal(.stopped, id: terminalID)
            notifications.removeAll {
                $0.sessionID == sessionID && $0.turnID == turnID
            }
            upsert(makeNotification(
                sessionID: sessionID,
                turnID: turnID,
                requestID: nil,
                cwd: cwd,
                result: "You interrupted this turn. Open Codex to review.",
                status: .stopped,
                chatTitle: chatTitle,
                projectName: projectName,
                date: date
            ))
        }
    }

    private mutating func rememberTerminal(_ status: CodexJobStatus, id: String) {
        terminalStatuses[id] = status
        recentTerminalIDs.removeAll { $0 == id }
        recentTerminalIDs.append(id)
        while recentTerminalIDs.count > 100 {
            terminalStatuses.removeValue(forKey: recentTerminalIDs.removeFirst())
        }
    }

    public func hasEndedTurn(sessionID: String, turnID: String?) -> Bool {
        guard let turnID else { return false }
        let id = Self.correlationID(sessionID: sessionID, turnID: turnID, requestID: nil)
        return terminalStatuses[id] != nil
    }

    public func visibleNotification(at date: Date = Date()) -> CodexJobNotification? {
        PriorityResolver.select(
            from: notifications,
            isVisible: {
                $0.status != .permissionRequired
                    || $0.permissionCallback?.isActive(at: date) == true
            },
            priority: { $0.status.priority },
            updatedAt: { $0.createdAt }
        )
    }

    public mutating func removeExpiredPermissionRequests(at date: Date = Date()) {
        notifications.removeAll { notification in
            notification.status == .permissionRequired
                && notification.permissionCallback?.isActive(at: date) != true
        }
    }

    public mutating func dismiss(_ id: String) {
        notifications.removeAll { $0.id == id }
    }

    public mutating func dismiss(_ token: CodexNotificationPresentationToken) {
        notifications.removeAll { token.matches($0) }
    }

    private mutating func makeNotification(
        sessionID: String,
        turnID: String?,
        requestID: String?,
        cwd: String?,
        result: String,
        status: CodexJobStatus,
        permissionCallback: CodexPermissionCallback? = nil,
        permissionDetails: CodexPermissionDetails? = nil,
        chatTitle: String? = nil,
        projectName: String? = nil,
        date: Date
    ) -> CodexJobNotification {
        let context = latestJobBySession[sessionID].flatMap { context in
            guard let turnID else { return context }
            return context.turnID == turnID ? context : nil
        }
        if context != nil {
            markJobContextRecentlyUsed(sessionID)
        }
        let effectiveTurnID = turnID ?? context?.turnID
        let resolvedChatTitle = chatTitle
            ?? context?.chatTitle
            ?? context?.title
            ?? Self.fallbackTitle(cwd: cwd ?? context?.cwd)
        let title = context?.title ?? resolvedChatTitle
        let userPrompt = context?.prompt ?? "Request details unavailable"
        let resolvedProjectName = projectName
            ?? context?.projectName
            ?? Self.projectName(cwd: cwd ?? context?.cwd)
        let id = Self.correlationID(
            sessionID: sessionID,
            turnID: effectiveTurnID,
            requestID: requestID
        )

        return CodexJobNotification(
            id: id,
            sessionID: sessionID,
            turnID: effectiveTurnID,
            requestID: requestID,
            jobTitle: title,
            resultSummary: CodexText.short(result, limit: 180),
            chatTitle: resolvedChatTitle,
            userPrompt: userPrompt,
            projectName: resolvedProjectName,
            status: status,
            permissionCallback: permissionCallback,
            permissionDetails: permissionDetails,
            createdAt: date
        )
    }

    private mutating func upsert(_ notification: CodexJobNotification) {
        notifications.removeAll { existing in
            existing.id == notification.id
                || (notification.requestID == nil
                    && notification.turnID == nil
                    && !existing.status.isPersistent
                    && existing.sessionID == notification.sessionID)
        }
        notifications.append(notification)

        while notifications.count > maximumNotifications {
            let evictionCandidates = notifications.indices.filter { index in
                let existing = notifications[index]
                return existing.status != .permissionRequired
                    || existing.permissionCallback?.isActive(
                        at: notification.createdAt
                    ) != true
            }
            guard let evictionIndex = evictionCandidates.min(by: {
                notifications[$0].createdAt < notifications[$1].createdAt
            }) else {
                break
            }
            notifications.remove(at: evictionIndex)
        }
    }

    private mutating func storeJobContext(
        _ context: JobContext,
        for sessionID: String
    ) {
        latestJobBySession[sessionID] = context
        markJobContextRecentlyUsed(sessionID)

        while recentJobSessionIDs.count > maximumJobContexts {
            let evictedSessionID = recentJobSessionIDs.removeFirst()
            latestJobBySession.removeValue(forKey: evictedSessionID)
        }
    }

    private mutating func markJobContextRecentlyUsed(_ sessionID: String) {
        recentJobSessionIDs.removeAll { $0 == sessionID }
        recentJobSessionIDs.append(sessionID)
    }

    private static func fallbackTitle(cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "Codex task" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Codex task" : "Codex · \(name)"
    }

    private static func projectName(cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "Codex" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Codex" : name
    }

    private static func correlationID(
        sessionID: String,
        turnID: String?,
        requestID: String?
    ) -> String {
        let turnComponent = turnID.map { "t\($0.utf8.count):\($0)" } ?? "t0:"
        let requestComponent = requestID.map { "r\($0.utf8.count):\($0)" } ?? "r0:"
        return "s\(sessionID.utf8.count):\(sessionID)|\(turnComponent)|\(requestComponent)"
    }

}

private struct JobContext: Equatable, Sendable {
    let turnID: String?
    let cwd: String?
    let prompt: String
    let title: String
    let chatTitle: String
    let projectName: String
}

private enum CodexText {
    static func userInstruction(from value: String) -> String {
        let lines = value.components(separatedBy: .newlines)
        guard let markerIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "## my request:"
        }) else {
            return value
        }

        let request = lines[(markerIndex + 1)...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return request.isEmpty ? value : request
    }

    static func normalized(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func short(_ value: String, limit: Int) -> String {
        let collapsed = normalized(value)

        guard collapsed.count > limit else {
            return collapsed.isEmpty ? "Codex task" : collapsed
        }
        let ellipsis = "..."
        return String(collapsed.prefix(max(0, limit - ellipsis.count))) + ellipsis
    }
}
