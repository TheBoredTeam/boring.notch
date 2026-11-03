/// The app and helper exchange only a delivery status, never raw CLI diagnostics.
public enum CodexReplyOutcome: String, Equatable, Sendable {
    case queued
    case queuedNeedsOpen
    case failed
    case unavailable
    case uncertain
}
