import Foundation
import XCTest
@testable import CodexNotificationsCore
@testable import CodexReplySupport

final class CodexReplyTests: XCTestCase {
    private let chatA = "00000000-0000-7000-8000-000000000001"
    private let chatB = "00000000-0000-7000-8000-000000000002"
    private let turn = "00000000-0000-7000-8000-000000000003"

    func testDraftsAndRequestsKeepExactDestinationAcrossTwoChats() throws {
        var state = CodexReplyState()
        state.edit("Reply A", for: notice(chatA))
        state.edit("Reply B", for: notice(chatB))
        let request = try XCTUnwrap(state.begin(sessionID: chatA))
        XCTAssertEqual(request.sessionID, chatA)
        XCTAssertEqual(request.text, "Reply A")
        XCTAssertNil(state.begin(sessionID: chatA), "Double submission must be ignored")
        state.edit("Replacement", for: notice(chatA))
        XCTAssertEqual(state.drafts[chatA]?.text, "Reply A")
        XCTAssertTrue(state.finish(request, with: .queued))
        XCTAssertEqual(state.drafts[chatA]?.text, "")
        XCTAssertEqual(state.drafts[chatB]?.text, "Reply B")
        XCTAssertEqual(state.drafts[chatA]?.origin, request.origin)
    }

    func testFailedSendRetainsDraftAndRetryHasANewRequestIdentity() throws {
        var state = CodexReplyState()
        state.edit("Original draft", for: notice(chatA))
        let first = try XCTUnwrap(state.begin(sessionID: chatA))
        state.finish(first, with: .failed)
        XCTAssertEqual(state.drafts[chatA]?.text, first.text)
        let retry = try XCTUnwrap(state.begin(sessionID: chatA))
        XCTAssertNotEqual(first.id, retry.id)
        XCTAssertFalse(state.finish(first, with: .queued), "A late callback must not finish the retry")
        XCTAssertEqual(state.drafts[chatA]?.delivery, .sending(retry.id))
    }

    func testUncertainDeliveryCannotBeRetriedUntilExplicitDiscard() throws {
        var state = CodexReplyState()
        state.edit("Keep this draft", for: notice(chatA))
        let request = try XCTUnwrap(state.begin(sessionID: chatA))
        state.finish(request, with: .uncertain)
        XCTAssertEqual(state.drafts[chatA]?.text, request.text)
        XCTAssertNil(state.begin(sessionID: chatA))
        state.edit("Accidental replacement", for: notice(chatA))
        XCTAssertEqual(state.drafts[chatA]?.text, request.text)
        state.discard(sessionID: chatA)
        XCTAssertNil(state.drafts[chatA])
    }

    func testWhitespaceAndShutdownAndLateCompletion() throws {
        var state = CodexReplyState()
        state.edit(" \n\t ", for: notice(chatA))
        XCTAssertNil(state.begin(sessionID: chatA))
        state.edit("Send", for: notice(chatA))
        let request = try XCTUnwrap(state.begin(sessionID: chatA))
        state.discard(sessionID: chatA)
        XCTAssertNotNil(state.drafts[chatA], "Do not drop a send already in flight")
        state.reset()
        state.edit("New draft", for: notice(chatA))
        XCTAssertFalse(state.finish(request, with: .queued))
        XCTAssertEqual(state.drafts[chatA]?.text, "New draft")
    }

    func testDraftOriginSurvivesANewerResponseInTheSameChat() throws {
        var state = CodexReplyState()
        let original = notice(chatA)
        state.edit("Unsent", for: original)
        state.edit("Still unsent", for: notice(chatA, date: Date(timeIntervalSince1970: 200)))
        let request = try XCTUnwrap(state.begin(sessionID: chatA))
        XCTAssertEqual(request.origin, CodexNotificationPresentationToken(original))
        XCTAssertEqual(request.turnID, turn)
    }

    func testAcceptedReplyLocksItsComposerUntilANewResponse() throws {
        for accepted: CodexReplyState.Delivery in [.queued, .queuedNeedsOpen] {
            var state = CodexReplyState()
            let original = notice(chatA)
            state.edit("First message", for: original)
            let first = try XCTUnwrap(state.begin(sessionID: chatA))
            XCTAssertNil(state.begin(sessionID: chatA), "Pending submission blocks duplicate clicks")
            XCTAssertTrue(state.finish(first, with: accepted))
            XCTAssertFalse(try XCTUnwrap(state.drafts[chatA]).delivery.allowsEditing)
            state.edit("Second message", for: original)
            XCTAssertEqual(state.drafts[chatA]?.text, "", "The accepted response must not accept another draft")
            XCTAssertNil(state.begin(sessionID: chatA))
            XCTAssertFalse(state.finish(first, with: .failed))
            state.expire(CodexNotificationPresentationToken(original))
            let nextResponse = CodexJobNotification(
                id: "next-response", sessionID: chatA, turnID: chatB, requestID: nil,
                jobTitle: "Fixture", resultSummary: "New response", status: .responseReady,
                createdAt: Date(timeIntervalSince1970: 200)
            )
            state.edit("Reply to new response", for: nextResponse)
            let next = try XCTUnwrap(state.begin(sessionID: chatA))
            XCTAssertEqual(next.origin, CodexNotificationPresentationToken(nextResponse))
            XCTAssertEqual(next.turnID, chatB)
            XCTAssertNotEqual(next.id, first.id)
        }
    }

    func testQueueAcknowledgementDistinguishesResumeFailureAndUnknownOutput() {
        XCTAssertEqual(CodexReplyTransport.classifyQueueOutput("Queued message fixture for thread fixture."), .queued)
        XCTAssertEqual(CodexReplyTransport.classifyQueueOutput("Queued message fixture.\nWarning: message was queued, but could not resume thread fixture"), .queuedNeedsOpen)
        XCTAssertEqual(CodexReplyTransport.classifyQueueOutput(""), .uncertain)
    }

    func testPointerExitCollapsesAfterDelayAndReentryCancelsIt() {
        var inactivity = CodexResponseInactivity()
        let start = Date(timeIntervalSince1970: 100)
        inactivity.update(isHovered: false, at: start)
        XCTAssertFalse(inactivity.shouldCollapse(at: start.addingTimeInterval(1.9)))
        XCTAssertTrue(inactivity.shouldCollapse(at: start.addingTimeInterval(2)))
        inactivity.update(isHovered: true, at: start.addingTimeInterval(1))
        XCTAssertFalse(inactivity.shouldCollapse(at: start.addingTimeInterval(10)))
    }

    func testKeyboardActivityOutsideRenewsTheCollapseDelay() {
        var inactivity = CodexResponseInactivity()
        let start = Date(timeIntervalSince1970: 100)
        inactivity.update(isHovered: false, at: start)
        inactivity.update(isHovered: false, at: start.addingTimeInterval(1.5))
        XCTAssertFalse(inactivity.shouldCollapse(at: start.addingTimeInterval(2)), "An old timer must not interrupt continued typing")
        XCTAssertTrue(inactivity.shouldCollapse(at: start.addingTimeInterval(3.5)))
        inactivity.reset()
        XCTAssertFalse(inactivity.shouldCollapse(at: start.addingTimeInterval(10)))
    }

    func testPromptExpiryClearsOnlyItsDraftAndReleasesItsRetainedNotice() {
        var replies = CodexReplyState()
        let original = notice(chatA)
        let other = notice(chatB)
        replies.edit("Draft A", for: original)
        replies.edit("Draft B", for: other)
        let notifications = CodexNotificationState(notifications: [other])
        XCTAssertEqual(replies.visibleNotification(in: notifications, retaining: original), original)
        XCTAssertEqual(replies.drafts[chatA]?.text, "Draft A", "Folding does not mutate the draft")
        replies.expire(CodexNotificationPresentationToken(original))
        XCTAssertNil(replies.drafts[chatA])
        XCTAssertEqual(replies.drafts[chatB]?.text, "Draft B")
        XCTAssertEqual(replies.visibleNotification(in: notifications, retaining: original), other)
    }

    func testAnExpiredSendCannotRestoreItsDraftOrAffectANewerReply() throws {
        var replies = CodexReplyState()
        let original = notice(chatA)
        replies.edit("Old reply", for: original)
        let old = try XCTUnwrap(replies.begin(sessionID: chatA))
        let oldToken = CodexNotificationPresentationToken(original)
        replies.expire(oldToken)
        XCTAssertNil(replies.drafts[chatA], "Expiry also releases an in-flight draft from the UI")
        let newer = notice(chatA, date: Date(timeIntervalSince1970: 200))
        replies.edit("New reply", for: newer)
        let current = try XCTUnwrap(replies.begin(sessionID: chatA))
        XCTAssertFalse(replies.finish(old, with: .failed))
        replies.expire(oldToken)
        XCTAssertEqual(replies.drafts[chatA]?.delivery, .sending(current.id))
        XCTAssertEqual(replies.drafts[chatA]?.text, "New reply")
    }

    func testExpiryClearsFailureUncertaintyAndAcceptedFeedback() throws {
        for delivery: CodexReplyState.Delivery in [.failed, .uncertain, .queued, .queuedNeedsOpen] {
            var replies = CodexReplyState()
            let original = notice(chatA)
            replies.edit("Draft", for: original)
            let request = try XCTUnwrap(replies.begin(sessionID: chatA))
            XCTAssertTrue(replies.finish(request, with: delivery))
            replies.expire(CodexNotificationPresentationToken(original))
            XCTAssertNil(replies.drafts[chatA])
            XCTAssertFalse(replies.finish(request, with: .queued))
        }
    }

    func testAnotherResponseWaitsForTheDraftAndPermissionStillPreemptsIt() {
        var replies = CodexReplyState()
        let original = notice(chatA)
        let other = notice(chatB, date: Date(timeIntervalSince1970: 200))
        replies.edit("Unsent reply", for: original)
        var notifications = CodexNotificationState(notifications: [other])
        XCTAssertEqual(replies.visibleNotification(in: notifications, retaining: original), original)
        let permission = CodexJobNotification(
            id: "permission", sessionID: chatB, turnID: turn, requestID: "fixture",
            jobTitle: "Fixture permission", resultSummary: "", status: .permissionRequired,
            permissionCallback: CodexPermissionCallback(port: 12345, token: "synthetic", expiresAt: .distantFuture),
            createdAt: Date()
        )
        notifications = CodexNotificationState(notifications: [other, permission])
        XCTAssertEqual(replies.visibleNotification(in: notifications, retaining: original), permission)
        notifications.dismiss(permission.id)
        XCTAssertEqual(replies.visibleNotification(in: notifications, retaining: original), original)
        XCTAssertEqual(replies.drafts[chatA]?.text, "Unsent reply")
        replies.discard(sessionID: chatA)
        XCTAssertEqual(replies.visibleNotification(in: notifications, retaining: original), other)
    }

    func testTransportPreservesQuotedMultilineUnicodeAndLeadingDashes() async throws {
        let text = "--leading option\n'quoted' \"double\" 你好 café $(not-a-command) `literal`"
        let fixture = try executable(expectedText: text)
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        var state = CodexReplyState()
        state.edit(text, for: notice(chatA))
        let request = try XCTUnwrap(state.begin(sessionID: chatA))
        let outcome = await CodexReplyTransport(executableURL: fixture).send(sessionID: request.sessionID, turnID: request.turnID, text: request.text)
        XCTAssertEqual(outcome, .queued)
        let received = try String(contentsOf: fixture.deletingLastPathComponent().appendingPathComponent("queued"), encoding: .utf8)
        XCTAssertEqual(Array(received.utf8), Array(text.utf8))
    }

    func testSharedSessionOrWrongTurnCannotQueueToARootConversation() async throws {
        for mode in ["shared-session", "wrong-turn", "exited"] {
            let fixture = try executable(expectedText: "Test", mode: mode)
            defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
            var state = CodexReplyState()
            state.edit("Test", for: notice(chatA))
            let request = try XCTUnwrap(state.begin(sessionID: chatA))
            let outcome = await CodexReplyTransport(executableURL: fixture).send(sessionID: request.sessionID, turnID: request.turnID, text: request.text)
            XCTAssertEqual(outcome, .unavailable)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.deletingLastPathComponent().appendingPathComponent("queued").path))
        }
    }

    private func notice(_ sessionID: String, date: Date = Date(timeIntervalSince1970: 100)) -> CodexJobNotification {
        CodexJobNotification(
            id: sessionID + turn, sessionID: sessionID, turnID: turn, requestID: nil,
            jobTitle: "Fixture", resultSummary: "Ready", status: .responseReady, createdAt: date
        )
    }

    private func executable(expectedText: String, mode: String = "success") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("codex-fixture")
        let expected = try JSONSerialization.data(withJSONObject: [expectedText])
        let expectedLiteral = String(decoding: expected, as: UTF8.self)
        let source = """
        #!/usr/bin/python3
        import sys,json,pathlib
        if '\(mode)' == 'exited': sys.exit(2)
        if sys.argv[1] == 'app-server':
            for line in sys.stdin:
                obj=json.loads(line)
                method=obj['method']
                if method == 'initialized': continue
                result={}
                if method == 'thread/read':
                    result={'thread':{'id':'\(chatA)','sessionId':'\(mode == "shared-session" ? chatB : chatA)','parentThreadId':None}}
                if method == 'thread/turns/list':
                    result={'data':[{'id':'\(mode == "wrong-turn" ? chatB : turn)'}]}
                print(json.dumps({'id':obj['id'],'result':result}),flush=True)
        else:
            pathlib.Path(__file__).with_name('queued').write_text(sys.argv[sys.argv.index('--message')+1])
            assert sys.argv[1]=='queue'
            assert sys.argv[sys.argv.index('--thread')+1]=='\(chatA)'
            assert sys.argv[sys.argv.index('--message')+1]==json.loads(r'''\(expectedLiteral)''')[0]
            print('Queued message fixture for thread fixture.',flush=True)
        """
        try source.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }
}
