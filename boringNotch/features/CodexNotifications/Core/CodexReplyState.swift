import Foundation

/// Drafts survive folding, and expire with their originating notification.
public struct CodexReplyState: Sendable {
    public struct Request: Equatable, Sendable {
        public let id: UUID
        public let sessionID: String
        public let turnID: String?
        public let origin: CodexNotificationPresentationToken
        public let text: String
    }

    public enum Delivery: Equatable, Sendable {
        case editing
        case sending(UUID)
        case queued
        case queuedNeedsOpen
        case failed
        case uncertain

        public var allowsEditing: Bool {
            switch self {
            case .editing, .failed: true
            case .sending, .queued, .queuedNeedsOpen, .uncertain: false
            }
        }
    }

    public struct Draft: Equatable, Sendable {
        public let sessionID: String
        public let turnID: String?
        public let origin: CodexNotificationPresentationToken
        public var text: String
        public var delivery: Delivery = .editing

        public var canSend: Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && delivery.allowsEditing
        }

        public var retainsNotification: Bool {
            !text.isEmpty || delivery != .editing
        }
    }

    public private(set) var drafts: [String: Draft] = [:]
    public init() {}

    public mutating func edit(_ text: String, for notification: CodexJobNotification) {
        var draft = drafts[notification.sessionID] ?? Draft(
            sessionID: notification.sessionID, turnID: notification.turnID,
            origin: CodexNotificationPresentationToken(notification), text: ""
        )
        guard draft.delivery.allowsEditing else { return }
        draft.text = text
        draft.delivery = .editing
        drafts[notification.sessionID] = text.isEmpty ? nil : draft
    }

    public mutating func begin(sessionID: String) -> Request? {
        guard var draft = drafts[sessionID], draft.canSend else { return nil }
        let id = UUID()
        draft.delivery = .sending(id)
        drafts[sessionID] = draft
        return Request(id: id, sessionID: sessionID, turnID: draft.turnID, origin: draft.origin, text: draft.text)
    }

    @discardableResult
    public mutating func finish(_ request: Request, with delivery: Delivery) -> Bool {
        guard var draft = drafts[request.sessionID], draft.origin == request.origin,
              draft.delivery == .sending(request.id) else { return false }
        draft.delivery = delivery
        if delivery == .queued || delivery == .queuedNeedsOpen { draft.text = "" }
        drafts[request.sessionID] = draft
        return true
    }

    public mutating func discard(sessionID: String) {
        // A running send cannot be cancelled by throwing away its draft.
        if case .sending = drafts[sessionID]?.delivery { return }
        drafts[sessionID] = nil
    }

    public mutating func reset() { drafts.removeAll() }

    public mutating func expire(_ token: CodexNotificationPresentationToken) {
        drafts = drafts.filter { $0.value.origin != token }
    }

    public func visibleNotification(
        in state: CodexNotificationState, retaining notification: CodexJobNotification?
    ) -> CodexJobNotification? {
        let candidate = state.visibleNotification()
        if candidate?.status == .permissionRequired { return candidate }
        if let notification, drafts[notification.sessionID]?.retainsNotification == true { return notification }
        return candidate
    }
}

/// Pointer re-entry cancels collapse; keyboard activity outside renews the delay.
public struct CodexResponseInactivity: Sendable {
    public private(set) var collapseDeadline: Date?
    public init() {}

    public mutating func update(isHovered: Bool, at date: Date = Date()) {
        collapseDeadline = isHovered ? nil : date.addingTimeInterval(CodexNotificationTiming.responseInactivityCollapseDelay)
    }

    public func shouldCollapse(at date: Date = Date()) -> Bool {
        collapseDeadline.map { date >= $0 } ?? false
    }

    public mutating func reset() { collapseDeadline = nil }
}
