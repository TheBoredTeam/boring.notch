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

public enum CodexRequiredAction: String, Equatable, Sendable {
    case permission
    case decision
    case manualCheck
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
        if status == .needsAction(.permission) {
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
        if status == .needsAction(.permission) {
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
    case needsAction(CodexRequiredAction)
    case failed
    case succeeded

    public var priority: Int {
        switch self {
        case .needsAction: 4
        case .failed: 3
        case .succeeded: 2
        }
    }

    public var isPersistent: Bool {
        switch self {
        case .needsAction(.permission): true
        case .needsAction(.decision), .needsAction(.manualCheck), .failed, .succeeded:
            false
        }
    }

    public var title: String {
        switch self {
        case .needsAction(.permission): "Permission Required"
        case .needsAction(.decision): "Decision Required"
        case .needsAction(.manualCheck): "Manual Check"
        case .failed: "Failure"
        case .succeeded: "Success"
        }
    }

    public var icon: String {
        switch self {
        case .needsAction(.permission): "lock.shield.fill"
        case .needsAction(.decision): "questionmark.circle.fill"
        case .needsAction(.manualCheck): "hand.tap.fill"
        case .failed: "xmark.circle.fill"
        case .succeeded: "checkmark.circle.fill"
        }
    }

    public var nextAction: String {
        switch self {
        case .needsAction(.permission), .needsAction(.decision):
            "Open Codex"
        case .needsAction(.manualCheck), .failed: "Review result"
        case .succeeded: "No action needed"
        }
    }
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
    case toolCompleted(
        sessionID: String,
        turnID: String?,
        cwd: String?,
        chatTitle: String? = nil,
        projectName: String? = nil
    )
    case stop(
        sessionID: String,
        turnID: String?,
        cwd: String?,
        result: String,
        reportedStatus: String? = nil,
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

        case "PostToolUse":
            return .toolCompleted(
                sessionID: sessionID,
                turnID: turnID,
                cwd: cwd,
                chatTitle: chatTitle,
                projectName: projectName
            )

        case "Stop":
            return .stop(
                sessionID: sessionID,
                turnID: turnID,
                cwd: cwd,
                result: nonemptyString(object["last_assistant_message"])
                    ?? nonemptyString(object["error"])
                    ?? nonemptyString(object["message"])
                    ?? "Codex stopped before completing the task.",
                reportedStatus: nonemptyString(object["status"]),
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
            guard !details.isAutoReviewed else { return }
            let notification = makeNotification(
                sessionID: sessionID,
                turnID: turnID,
                requestID: requestID,
                cwd: cwd,
                result: details.summary,
                status: .needsAction(.permission),
                permissionCallback: callback,
                permissionDetails: details,
                chatTitle: chatTitle,
                projectName: projectName,
                date: date
            )
            upsert(notification)

        case .toolCompleted:
            // PermissionRequest and PostToolUse do not share a reliable request ID.
            // Keep live approvals until an explicit decision, terminal event, or expiry.
            break

        case .stop(
            let sessionID,
            let turnID,
            let cwd,
            let result,
            let reportedStatus,
            let chatTitle,
            let projectName
        ):
            notifications.removeAll { notification in
                guard notification.status == .needsAction(.permission),
                      notification.sessionID == sessionID else {
                    return false
                }
                guard let turnID else { return true }
                return notification.turnID == turnID
            }
            let status = Self.classify(result: result, reportedStatus: reportedStatus)
            let notification = makeNotification(
                sessionID: sessionID,
                turnID: turnID,
                requestID: nil,
                cwd: cwd,
                result: result,
                status: status,
                chatTitle: chatTitle,
                projectName: projectName,
                date: date
            )
            upsert(notification)
        }
    }

    public func visibleNotification(at date: Date = Date()) -> CodexJobNotification? {
        PriorityResolver.select(
            from: notifications,
            isVisible: {
                $0.status != .needsAction(.permission)
                    || $0.permissionCallback?.isActive(at: date) == true
            },
            priority: { $0.status.priority },
            updatedAt: { $0.createdAt }
        )
    }

    public mutating func removeExpiredPermissionRequests(at date: Date = Date()) {
        notifications.removeAll { notification in
            notification.status == .needsAction(.permission)
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
                    && existing.sessionID == notification.sessionID)
        }
        notifications.append(notification)

        while notifications.count > maximumNotifications {
            let evictionCandidates = notifications.indices.filter { index in
                let existing = notifications[index]
                return existing.status != .needsAction(.permission)
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

    private static func classify(
        result: String,
        reportedStatus: String?
    ) -> CodexJobStatus {
        let normalizedStatus = reportedStatus?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let text = result
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let failureText = text
            .replacingOccurrences(of: "no tests failed", with: "")
            .replacingOccurrences(of: "0 tests failed", with: "")
            .replacingOccurrences(of: "zero tests failed", with: "")
        let failureMarkers = [
            "build failed", "tests failed", "test failed", "failed to",
            "could not complete", "couldn't complete", "unable to complete",
            "the task failed", "encountered an error", "interrupted",
            "aborted", "cancelled", "canceled", "terminated",
            "stopped before completing", "stopped by user", "error:",
            "command failed", "status: failed", "failed (exit code"
        ]
        let hasExplicitSuccessStatus = ["succeeded", "success"].contains(normalizedStatus)
        if ["failed", "error", "cancelled", "canceled"].contains(normalizedStatus)
            || (!hasExplicitSuccessStatus
                && failureMarkers.contains(where: failureText.contains)) {
            return .failed
        }

        let manualMarkers = [
            "manually verify", "verify manually", "test manually",
            "please verify", "please test", "please manually review",
            "manually review", "review and approve", "approve or reject",
            "wait for manual review", "wait for manual verification",
            "manual review required", "manual verification required",
            "manual test required", "requires manual review",
            "requires manual verification", "needs manual review",
            "needs manual verification", "manual review and approval"
        ]
        if manualMarkers.contains(where: {
            containsAffirmativeMarker($0, in: text)
        }) {
            return .needsAction(.manualCheck)
        }

        let decisionMarkers = [
            "need your decision", "your decision is needed", "please choose",
            "please decide", "i need your input", "need your input",
            "your input is needed", "waiting for your input",
            "waiting for your choice", "waiting for your decision",
            "waiting for your response", "awaiting your response",
            "select an option", "choose an option", "pick an option",
            "choose one", "select one", "pick one", "make a choice",
            "need a decision", "decision from you", "your choice",
            "requires your input", "your input is required",
            "which option", "which one", "which should i", "which do you prefer",
            "which would you prefer", "do you prefer", "would you prefer",
            "what would you like me to", "what should i do",
            "let me know whether", "tell me which", "tell me whether",
            "let me know what you prefer", "what do you prefer",
            "what would you choose", "please confirm", "confirm whether",
            "confirm if",
            "should i ", "would you like me to", "do you want me to",
            "how should i proceed", "how should we proceed",
            "how would you like to proceed", "how would you like me to proceed",
            "choose a or b", "select a or b", "pick a or b",
            "choose between"
        ]
        let directQuestionMarkers = [
            "which ", "what ", "how ", "should i ", "would you ",
            "do you ", "can i ", "may i ", "shall i "
        ]
        if decisionMarkers.contains(where: {
            containsAffirmativeMarker($0, in: text)
        })
            || (text.hasSuffix("?") && directQuestionMarkers.contains(where: text.contains)) {
            return .needsAction(.decision)
        }

        if ["succeeded", "success"].contains(normalizedStatus) {
            return .succeeded
        }

        let successMarkers = [
            "build succeeded", "tests passed", "all tests passed",
            "completed successfully", "successfully completed"
        ]
        if successMarkers.contains(where: text.contains) {
            return .succeeded
        }
        return .succeeded
    }

    private static func containsAffirmativeMarker(
        _ marker: String,
        in text: String
    ) -> Bool {
        var searchStart = text.startIndex

        while let range = text.range(
            of: marker,
            range: searchStart..<text.endIndex
        ) {
            if !isNegated(at: range.lowerBound, marker: marker, in: text) {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isNegated(
        at markerStart: String.Index,
        marker: String,
        in text: String
    ) -> Bool {
        let prefix = text[..<markerStart]
        let clauseSeparators = CharacterSet(charactersIn: ".!?;:,\n\r")
        let clauseStart = prefix.lastIndex { character in
            character.unicodeScalars.contains { clauseSeparators.contains($0) }
        }.map { text.index(after: $0) } ?? text.startIndex
        let clause = text[clauseStart..<markerStart]
            .replacingOccurrences(of: "’", with: "'")
            .lowercased()
        let tokenCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "'")
        )
        var tokens = clause.components(
            separatedBy: tokenCharacters.inverted
        ).filter { !$0.isEmpty }

        let unconditionalBoundaries: Set<String> = ["but", "however", "yet"]
        let clauseBoundaries: Set<String> = ["and", "because", "so"]
        let clauseStarters: Set<String> = [
            "he", "i", "it", "please", "she", "that", "they", "this",
            "those", "we", "you", "your",
        ]
        let markerFirstToken = marker.components(
            separatedBy: tokenCharacters.inverted
        ).first { !$0.isEmpty }
        let boundaryIndex = tokens.indices.reversed().first { index in
            let token = tokens[index]
            if unconditionalBoundaries.contains(token) { return true }
            guard clauseBoundaries.contains(token) else { return false }
            let followingTokens = tokens[tokens.index(after: index)...]
            return followingTokens.contains(where: clauseStarters.contains)
                || markerFirstToken.map(clauseStarters.contains) == true
        }
        if let boundaryIndex {
            tokens = Array(tokens[tokens.index(after: boundaryIndex)...])
        }

        let negationReach: [String: Int] = [
            "no": 2,
            "not": 5,
            "never": 5,
            "without": 3,
            "cannot": 5,
            "don't": 5,
            "doesn't": 5,
            "didn't": 5,
            "won't": 5,
            "can't": 5,
        ]
        for index in tokens.indices.reversed() {
            guard let reach = negationReach[tokens[index]] else { continue }
            if tokens[index] == "not",
               tokens.indices.contains(index + 1),
               tokens[index + 1] == "only" {
                continue
            }
            let distance = tokens.distance(from: index, to: tokens.endIndex) - 1
            return distance <= reach
        }
        return false
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
