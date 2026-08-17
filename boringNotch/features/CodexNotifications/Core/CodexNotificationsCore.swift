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
    public static let nativePermissionInspectionGrace: TimeInterval = 0.75
    public static let nativePermissionAppearanceTimeout: TimeInterval = 10

    public static func transitionDuration(
        animationSpeedMultiplier: Double,
        animationsEnabled: Bool
    ) -> TimeInterval {
        guard animationsEnabled else { return 0 }
        let speed = max(animationSpeedMultiplier, 0.01)
        return transitionAnimationResponse / speed
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

public enum CodexPermissionControl: String, Equatable, Sendable {
    case accessibility
}

public enum CodexPermissionDecision: String, Sendable {
    case allow
    case deny
}

public struct CodexPermissionDetails: Equatable, Sendable {
    public let toolName: String
    public let description: String?
    public let command: String?
    public let rawCommand: String?
    public let additionalInput: String?

    public init(
        toolName: String,
        description: String? = nil,
        command: String? = nil,
        rawCommand: String? = nil,
        additionalInput: String? = nil
    ) {
        self.toolName = toolName
        self.description = description
        self.command = command
        self.rawCommand = rawCommand
        self.additionalInput = additionalInput
    }

    public var summary: String {
        description
            ?? command
            ?? additionalInput
            ?? "Codex needs permission to use \(toolName)."
    }

    public var accessibilityMatchCandidates: [String] {
        var candidates: [String] = []
        for candidate in [description, rawCommand, command].compactMap({ $0 })
            where !candidate.isEmpty && !candidates.contains(candidate) {
            candidates.append(candidate)
        }
        return candidates
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
    public let chatTitle: String
    public let jobTitle: String
    public let userPrompt: String
    public let projectName: String
    public let resultSummary: String
    public let status: CodexJobStatus
    public let permissionControl: CodexPermissionControl?
    public let permissionDetails: CodexPermissionDetails?
    public let nativePermissionConfirmed: Bool
    public let createdAt: Date

    public init(
        id: String,
        sessionID: String,
        turnID: String?,
        jobTitle: String,
        resultSummary: String,
        chatTitle: String? = nil,
        userPrompt: String? = nil,
        projectName: String = "Codex",
        status: CodexJobStatus,
        permissionControl: CodexPermissionControl? = nil,
        permissionDetails: CodexPermissionDetails? = nil,
        nativePermissionConfirmed: Bool = true,
        createdAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.turnID = turnID
        self.chatTitle = chatTitle ?? jobTitle
        self.jobTitle = jobTitle
        self.userPrompt = userPrompt ?? jobTitle
        self.projectName = projectName
        self.resultSummary = resultSummary
        self.status = status
        self.permissionControl = permissionControl
        self.permissionDetails = permissionDetails
        self.nativePermissionConfirmed = nativePermissionConfirmed
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
        cwd: String?,
        details: CodexPermissionDetails,
        control: CodexPermissionControl? = nil,
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
            let toolName = nonemptyString(object["tool_name"]) ?? "Codex"
            return .permissionRequest(
                sessionID: sessionID,
                turnID: turnID,
                cwd: cwd,
                details: permissionDetails(from: object, toolName: toolName),
                control: permissionControl(from: object),
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
        guard let input = object["tool_input"] as? [String: Any] else {
            return CodexPermissionDetails(toolName: toolName)
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
            additionalInput: additionalInput
        )
    }

    private static func permissionControl(
        from object: [String: Any]
    ) -> CodexPermissionControl? {
        guard let approval = object["boring_notch_approval"] as? [String: Any],
              let controlValue = approval["control"] as? String,
              let control = CodexPermissionControl(rawValue: controlValue) else {
            return nil
        }
        return control
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
    private let maximumNotifications = 20

    public init(notifications: [CodexJobNotification] = []) {
        self.notifications = notifications
        latestJobBySession = [:]
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
            latestJobBySession[sessionID] = JobContext(
                turnID: turnID,
                cwd: cwd,
                prompt: userInstruction,
                title: CodexText.short(userInstruction, limit: 84),
                chatTitle: chatTitle
                    ?? CodexText.short(userInstruction, limit: 84),
                projectName: projectName ?? Self.projectName(cwd: cwd)
            )

        case .permissionRequest(
            let sessionID,
            let turnID,
            let cwd,
            let details,
            let control,
            let chatTitle,
            let projectName
        ):
            let notification = makeNotification(
                sessionID: sessionID,
                turnID: turnID,
                cwd: cwd,
                result: details.summary,
                status: .needsAction(.permission),
                permissionControl: control,
                permissionDetails: details,
                nativePermissionConfirmed: false,
                chatTitle: chatTitle,
                projectName: projectName,
                date: date
            )
            upsert(notification)

        case .toolCompleted(let sessionID, let turnID, _, _, _):
            notifications.removeAll { notification in
                guard notification.status == .needsAction(.permission),
                      notification.sessionID == sessionID else {
                    return false
                }
                guard let turnID else { return true }
                return notification.turnID == turnID
            }

        case .stop(
            let sessionID,
            let turnID,
            let cwd,
            let result,
            let reportedStatus,
            let chatTitle,
            let projectName
        ):
            let status = Self.classify(result: result, reportedStatus: reportedStatus)
            let notification = makeNotification(
                sessionID: sessionID,
                turnID: turnID,
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

    public func visibleNotification() -> CodexJobNotification? {
        PriorityResolver.select(
            from: notifications,
            isVisible: {
                $0.status != .needsAction(.permission)
                    || $0.nativePermissionConfirmed
            },
            priority: { $0.status.priority },
            updatedAt: { $0.createdAt }
        )
    }

    public func nativePermissionNotification() -> CodexJobNotification? {
        PriorityResolver.select(
            from: notifications,
            isVisible: {
                $0.status == .needsAction(.permission)
                    && $0.permissionControl == .accessibility
            },
            priority: { $0.nativePermissionConfirmed ? 1 : 0 },
            updatedAt: { $0.createdAt }
        )
    }

    public mutating func confirmNativePermission(_ id: String) {
        guard let index = notifications.firstIndex(where: {
            $0.id == id
                && $0.status == .needsAction(.permission)
                && $0.permissionControl == .accessibility
                && !$0.nativePermissionConfirmed
        }) else {
            return
        }

        let notification = notifications[index]
        notifications[index] = CodexJobNotification(
            id: notification.id,
            sessionID: notification.sessionID,
            turnID: notification.turnID,
            jobTitle: notification.jobTitle,
            resultSummary: notification.resultSummary,
            chatTitle: notification.chatTitle,
            userPrompt: notification.userPrompt,
            projectName: notification.projectName,
            status: notification.status,
            permissionControl: notification.permissionControl,
            permissionDetails: notification.permissionDetails,
            nativePermissionConfirmed: true,
            createdAt: notification.createdAt
        )
    }

    public mutating func dismiss(_ id: String) {
        notifications.removeAll { $0.id == id }
    }

    private func makeNotification(
        sessionID: String,
        turnID: String?,
        cwd: String?,
        result: String,
        status: CodexJobStatus,
        permissionControl: CodexPermissionControl? = nil,
        permissionDetails: CodexPermissionDetails? = nil,
        nativePermissionConfirmed: Bool = true,
        chatTitle: String? = nil,
        projectName: String? = nil,
        date: Date
    ) -> CodexJobNotification {
        let context = latestJobBySession[sessionID]
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
        let id = Self.correlationID(sessionID: sessionID, turnID: effectiveTurnID)

        return CodexJobNotification(
            id: id,
            sessionID: sessionID,
            turnID: effectiveTurnID,
            jobTitle: title,
            resultSummary: CodexText.short(result, limit: 180),
            chatTitle: resolvedChatTitle,
            userPrompt: userPrompt,
            projectName: resolvedProjectName,
            status: status,
            permissionControl: permissionControl,
            permissionDetails: permissionDetails,
            nativePermissionConfirmed: nativePermissionConfirmed,
            createdAt: date
        )
    }

    private mutating func upsert(_ notification: CodexJobNotification) {
        notifications.removeAll { existing in
            existing.id == notification.id
                || (notification.turnID == nil && existing.sessionID == notification.sessionID)
        }
        notifications.append(notification)

        if notifications.count > maximumNotifications {
            notifications.sort { $0.createdAt > $1.createdAt }
            notifications.removeLast(notifications.count - maximumNotifications)
        }
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

    private static func correlationID(sessionID: String, turnID: String?) -> String {
        if let turnID, !turnID.isEmpty {
            return "s\(sessionID.utf8.count):\(sessionID)|t\(turnID.utf8.count):\(turnID)"
        }
        return "s\(sessionID.utf8.count):\(sessionID)|t0:"
    }

    private static func classify(
        result: String,
        reportedStatus: String?
    ) -> CodexJobStatus {
        if let normalizedStatus = reportedStatus?.lowercased() {
            if ["failed", "error", "cancelled", "canceled"].contains(normalizedStatus) {
                return .failed
            }
            if ["succeeded", "success"].contains(normalizedStatus) {
                return .succeeded
            }
        }

        let text = result.lowercased()
        let failureText = text
            .replacingOccurrences(of: "no tests failed", with: "")
            .replacingOccurrences(of: "0 tests failed", with: "")
            .replacingOccurrences(of: "zero tests failed", with: "")
        let failureMarkers = [
            "build failed", "tests failed", "test failed", "failed to",
            "could not complete", "couldn't complete", "unable to complete",
            "the task failed", "encountered an error", "interrupted",
            "aborted", "cancelled", "canceled", "terminated",
            "stopped before completing", "stopped by user"
        ]
        if failureMarkers.contains(where: failureText.contains) {
            return .failed
        }

        let manualMarkers = [
            "manual verification", "manually verify", "verify manually",
            "manual test", "test manually", "please verify", "please test"
        ]
        if manualMarkers.contains(where: text.contains) {
            return .needsAction(.manualCheck)
        }

        let decisionMarkers = [
            "need your decision", "your decision is needed", "please choose",
            "which option", "choose whether", "let me know whether"
        ]
        if decisionMarkers.contains(where: text.contains) {
            return .needsAction(.decision)
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
