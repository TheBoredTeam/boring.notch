import XCTest
@testable import CodexNotificationsCore

final class CodexResponsePreviewTests: XCTestCase {
    private func stop(_ message: String?, truncated: Bool = false, session: String = "fixture", turn: String = "turn") throws -> CodexHookEvent {
        var payload: [String: Any] = [
            "hook_event_name": "Stop", "session_id": session, "turn_id": turn,
            "response_truncated": truncated,
        ]
        payload["last_assistant_message"] = message
        return try CodexHookEventParser.parse(JSONSerialization.data(withJSONObject: payload))
    }

    func testRetainsExactMarkdownSeparatelyFromCompactSummary() throws {
        let source = "  # Heading\n\n| A | B |\n| --- | --- |\n| café | 你好 |\n\n```swift\nlet x = 1\n```\n"
        var state = CodexNotificationState()
        state.reduce(try stop(source))
        let notification = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(notification.responsePreview?.source, source)
        XCTAssertEqual(notification.responsePreview?.isTruncated, false)
        XCTAssertFalse(notification.resultSummary.contains("\n"))
        XCTAssertEqual(notification.status, .responseReady)
    }

    func testUnicodeCodePointCapAndExplicitOmissionState() {
        for unit in ["a", "🙂", "e\u{301}"] {
            let atLimit = String(repeating: unit, count: 16_000 / unit.unicodeScalars.count)
            XCTAssertEqual(CodexResponsePreview(source: atLimit).source, atLimit)
            XCTAssertFalse(CodexResponsePreview(source: atLimit).isTruncated)
            let above = CodexResponsePreview(source: atLimit + "🙂")
            XCTAssertEqual(above.source, atLimit)
            XCTAssertTrue(above.isTruncated)
        }
        XCTAssertTrue(CodexResponsePreview(source: "retained", isTruncated: true).isTruncated)
        XCTAssertFalse(CodexResponsePreview(source: "short").isTruncated)
    }

    func testMissingAndWhitespaceResponsesHaveNoInventedPreview() throws {
        for source in [nil, "", " \n\t"] as [String?] {
            var state = CodexNotificationState()
            state.reduce(try stop(source))
            XCTAssertEqual(state.visibleNotification()?.status, .update)
            XCTAssertNil(state.visibleNotification()?.responsePreview)
        }
    }

    func testTruncatedIncompleteMarkdownKeepsTheExactPrefix() throws {
        for source in ["```swift\nlet partial =", "| Column | Other |\n| --- | --- |\n| partial"] {
            var state = CodexNotificationState()
            state.reduce(try stop(source, truncated: true))
            XCTAssertEqual(state.visibleNotification()?.responsePreview, .init(source: source, isTruncated: true))
        }
    }

    func testPreviewsStayCorrelatedAndDisappearWithTheirNotification() throws {
        var state = CodexNotificationState()
        state.reduce(try stop("First chat", session: "first"), at: Date(timeIntervalSince1970: 1))
        state.reduce(try stop("Second chat", session: "second"), at: Date(timeIntervalSince1970: 2))
        let second = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(second.responsePreview?.source, "Second chat")
        XCTAssertEqual(CodexApplicationRoute.threadURL(sessionID: second.sessionID)?.absoluteString, "codex://threads/second")
        state.dismiss(CodexNotificationPresentationToken(second))
        state.reduce(try stop("Duplicate", session: "second"))
        XCTAssertEqual(state.notifications.count, 1)
        XCTAssertEqual(state.visibleNotification()?.responsePreview?.source, "First chat")
        state.reduce(.userPrompt(sessionID: "first", turnID: "next", cwd: nil, prompt: "Continue"))
        XCTAssertTrue(state.notifications.isEmpty)
    }

    func testInterruptReplacesResponseWithNoStalePreview() throws {
        var state = CodexNotificationState()
        state.reduce(try stop("Final reply"))
        state.reduce(.interrupt(sessionID: "fixture", turnID: "turn", cwd: nil))
        state.reduce(try stop("Late reply"))
        XCTAssertEqual(state.visibleNotification()?.status, .stopped)
        XCTAssertNil(state.visibleNotification()?.responsePreview)
    }

    func testResponseActivationExpandsAndOtherPassiveActivationKeepsItsRoute() {
        XCTAssertEqual(CodexClosedActivityTapRouting(status: .responseReady, hasResponsePreview: true), .expandNotch)
        XCTAssertEqual(CodexClosedActivityTapRouting(status: .update), .openCodex)
        XCTAssertEqual(CodexClosedActivityTapRouting(status: .stopped), .openCodex)
        XCTAssertEqual(CodexClosedActivityTapRouting(status: .permissionRequired), .expandNotch)
        XCTAssertEqual(CodexClosedActivityAccessibility(
            status: .responseReady, projectName: "Fixture", hasResponsePreview: true
        ).hint, "Activate to read this response in Boring Notch.")
    }

    func testDetailOwnershipKeepsAnotherDisplayOpenAndRejectsAStaleCollapse() throws {
        var state = CodexNotificationState()
        state.reduce(try stop("First"), at: Date(timeIntervalSince1970: 1))
        let first = CodexNotificationPresentationToken(try XCTUnwrap(state.visibleNotification()))
        var presentation = CodexNotificationDetailPresentation()
        presentation.present(first, surfaceID: "display-one")
        presentation.present(first, surfaceID: "display-two")
        XCTAssertFalse(presentation.dismiss(first, surfaceID: "display-one"))
        XCTAssertEqual(presentation.token, first)
        XCTAssertEqual(presentation.surfaceIDs, ["display-two"])

        state.reduce(try stop("Replacement", session: "other"), at: Date(timeIntervalSince1970: 2))
        let replacement = CodexNotificationPresentationToken(try XCTUnwrap(state.visibleNotification()))
        presentation.present(replacement, surfaceID: "display-two")
        XCTAssertFalse(presentation.dismiss(first, surfaceID: "display-two"))
        XCTAssertEqual(presentation.token, replacement)
        XCTAssertTrue(presentation.dismiss(replacement, surfaceID: "display-two"))
        XCTAssertNil(presentation.token)
    }

    func testReplacementOrDismissalClearsExpandedDetailOwnership() throws {
        var state = CodexNotificationState()
        state.reduce(try stop("First"))
        let token = CodexNotificationPresentationToken(try XCTUnwrap(state.visibleNotification()))
        var presentation = CodexNotificationDetailPresentation()
        presentation.present(token, surfaceID: "display")
        presentation.retainOnly(token)
        XCTAssertEqual(presentation.token, token)
        presentation.retainOnly(nil)
        XCTAssertNil(presentation.token)
        XCTAssertTrue(presentation.surfaceIDs.isEmpty)
    }
}
