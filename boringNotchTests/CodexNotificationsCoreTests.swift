import XCTest
@testable import CodexNotificationsCore
@testable import CodexHookTrustState

final class CodexNotificationsCoreTests: XCTestCase {
    private let permissionRequestID = "0123456789abcdef0123456789abcdef"
    private let permissionCallback = CodexPermissionCallback(
        port: 49_152,
        token: "abcdefghijklmnopqrstuvwxyzABCDEF",
        expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
    )

    private func parsePermissionPayload(
        _ payload: String,
        requestID: String? = nil
    ) throws -> CodexHookEvent {
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )
        object["boring_notch_auth"] = [
            "timestamp": 1_000,
            "nonce": requestID ?? permissionRequestID,
        ]
        return try CodexHookEventParser.parse(
            JSONSerialization.data(withJSONObject: object)
        )
    }

    private func productionStopStatus(
        _ message: String,
        sessionID: String = UUID().uuidString
    ) throws -> CodexJobStatus? {
        let payload: [String: Any] = [
            "hook_event_name": "Stop",
            "session_id": sessionID,
            "turn_id": "turn-1",
            "last_assistant_message": message,
        ]
        var state = CodexNotificationState()
        state.reduce(try CodexHookEventParser.parse(
            JSONSerialization.data(withJSONObject: payload)
        ))
        return state.visibleNotification()?.status
    }

    private struct Candidate: Equatable {
        let id: String
        let visible: Bool
        let priority: Int
        let updatedAt: Date
    }

    func testCodexHookTargetsBoringNotchWhenOpeningAuthenticatedEventURL() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let helperSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("BoringNotchXPCHelper")
                .appendingPathComponent("BoringNotchXPCHelper.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            helperSource.contains(
                """
                                "/usr/bin/open",
                                "-g",
                                "-b",
                                "theboringteam.boringnotch",
                                "boringnotch://codex-event?payload="
                """
            ),
            "Authenticated Codex URLs must be delivered to Boring Notch by bundle identifier."
        )
    }

    func testDisabledHookIsNotTrustedEvenWithAMatchingHash() {
        let section = "/Users/example/.codex/hooks.json:permission_request:0:0"
        let currentHash = "sha256:\(String(repeating: "a", count: 64))"
        let configuration = """
        [hooks.state."\(section)"]
        trusted_hash = "\(currentHash)"
        enabled = false
        """

        let state = CodexHookTrustState(configuration: configuration)

        XCTAssertFalse(state.areTrusted([section], matching: [section: currentHash]))
    }

    func testDisabledHookWithInlineCommentIsNotTrusted() {
        let section = "/Users/example/.codex/hooks.json:permission_request:0:0"
        let currentHash = "sha256:\(String(repeating: "a", count: 64))"
        let configuration = """
        [hooks.state."\(section)"]
        trusted_hash = "\(currentHash)"
        enabled = false # Disabled while reviewing this hook.
        """

        let state = CodexHookTrustState(configuration: configuration)

        XCTAssertFalse(state.areTrusted([section], matching: [section: currentHash]))
    }

    func testInlineCommentsDoNotConsumeHashCharactersInsideQuotedSectionNames() {
        let section = "/Users/example/#hooks.json:stop:0:0"
        let currentHash = "sha256:\(String(repeating: "b", count: 64))"
        let configuration = """
        [hooks.state."\(section)"] # Path includes a hash character.
        trusted_hash = "\(currentHash)" # Approved by the user.
        """

        let state = CodexHookTrustState(configuration: configuration)

        XCTAssertTrue(state.areTrusted([section], matching: [section: currentHash]))
    }

    func testHookWithValidHashAndNoDisabledFlagIsTrusted() {
        let section = "/Users/example/.codex/hooks.json:stop:0:0"
        let currentHash = "sha256:\(String(repeating: "b", count: 64))"
        let configuration = """
        [hooks.state."\(section)"]
        trusted_hash = "\(currentHash)"
        """

        let state = CodexHookTrustState(configuration: configuration)

        XCTAssertTrue(state.areTrusted([section], matching: [section: currentHash]))
    }

    func testHookWithMismatchedCurrentHashIsNotTrusted() {
        let section = "/Users/example/.codex/hooks.json:stop:0:0"
        let trustedHash = "sha256:\(String(repeating: "b", count: 64))"
        let currentHash = "sha256:\(String(repeating: "c", count: 64))"
        let configuration = """
        [hooks.state."\(section)"]
        trusted_hash = "\(trustedHash)"
        """

        let state = CodexHookTrustState(configuration: configuration)

        XCTAssertFalse(state.areTrusted([section], matching: [section: currentHash]))
    }

    func testCurrentHashMatchesCodexNormalizedHookFingerprint() {
        XCTAssertEqual(
            CodexHookTrustState.currentHash(
                eventName: "stop",
                command: "echo hello",
                timeout: 5
            ),
            "sha256:c6fba7cbd9f8faf1955357f62b47f4c4463889ebab2f1a7ddf3473acf4fe6837"
        )
    }

    func testCurrentHashIgnoresMatcherForEventsWithoutMatcherSupport() {
        for eventName in ["stop", "user_prompt_submit"] {
            let withoutMatcher = CodexHookTrustState.currentHash(
                eventName: eventName,
                command: "echo hello",
                timeout: 5
            )
            let withMatcher = CodexHookTrustState.currentHash(
                eventName: eventName,
                matcher: "^ignored$",
                command: "echo hello",
                timeout: 5
            )

            XCTAssertEqual(withMatcher, withoutMatcher, eventName)
        }
    }

    func testCurrentHashPreservesMatcherForEventsWithMatcherSupport() {
        for eventName in ["permission_request", "post_tool_use"] {
            let withoutMatcher = CodexHookTrustState.currentHash(
                eventName: eventName,
                command: "echo hello",
                timeout: 5
            )
            let withMatcher = CodexHookTrustState.currentHash(
                eventName: eventName,
                matcher: "Bash",
                command: "echo hello",
                timeout: 5
            )

            XCTAssertNotEqual(withMatcher, withoutMatcher, eventName)
        }
    }

    func testStatusIconsMatchNotchNotificationGlyphs() {
        XCTAssertEqual(CodexJobStatus.succeeded.icon, "checkmark.circle.fill")
        XCTAssertEqual(CodexJobStatus.failed.icon, "xmark.circle.fill")
        XCTAssertEqual(CodexJobStatus.needsAction(.permission).icon, "lock.shield.fill")
        XCTAssertEqual(CodexJobStatus.needsAction(.decision).icon, "questionmark.circle.fill")
        XCTAssertEqual(CodexJobStatus.needsAction(.manualCheck).icon, "hand.tap.fill")
    }

    func testPriorityResolverSelectsHighestVisibleCandidate() {
        let selected = PriorityResolver.select(
            from: [
                Candidate(id: "hidden", visible: false, priority: 10, updatedAt: .distantFuture),
                Candidate(id: "music", visible: true, priority: 2, updatedAt: .distantFuture),
                Candidate(id: "approval", visible: true, priority: 4, updatedAt: .distantPast)
            ],
            isVisible: { $0.visible },
            priority: { $0.priority },
            updatedAt: { $0.updatedAt }
        )

        XCTAssertEqual(selected?.id, "approval")
    }

    func testPriorityResolverPrefersNewestCandidateAtSamePriority() {
        let selected = PriorityResolver.select(
            from: [
                Candidate(id: "music", visible: true, priority: 2, updatedAt: .distantPast),
                Candidate(id: "codex", visible: true, priority: 2, updatedAt: .distantFuture)
            ],
            isVisible: { $0.visible },
            priority: { $0.priority },
            updatedAt: { $0.updatedAt }
        )

        XCTAssertEqual(selected?.id, "codex")
    }

    func testParsesPromptAndUsesItAsPermissionJobTitle() throws {
        var state = CodexNotificationState()
        state.reduce(try CodexHookEventParser.parse(#"""
        {
            "hook_event_name":"UserPromptSubmit",
            "session_id":"session-1",
            "turn_id":"turn-1",
            "cwd":"/tmp/boring.notch",
            "prompt":"Fix the extension conflict in PR #970"
        }
        """#))
        state.reduce(try parsePermissionPayload(#"""
        {
            "hook_event_name":"PermissionRequest",
            "session_id":"session-1",
            "turn_id":"turn-1",
            "cwd":"/tmp/boring.notch",
            "chat_title":"Fix Codex permission relay",
            "project_name":"Boring Notch Contribution",
            "tool_name":"Bash",
            "tool_input":{
                "description":"May I build the Debug app for visual verification?",
                "command":"xcodebuild -scheme boringNotch build",
                "sandbox_permissions":"require_escalated"
            },
            "boring_notch_approval": {
                "port": 49152,
                "token": "abcdefghijklmnopqrstuvwxyzABCDEF",
                "expires_at": 4102444800
            }
        }
        """#))

        let notice = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(notice.jobTitle, "Fix the extension conflict in PR #970")
        XCTAssertEqual(notice.chatTitle, "Fix Codex permission relay")
        XCTAssertEqual(notice.userPrompt, "Fix the extension conflict in PR #970")
        XCTAssertEqual(notice.projectName, "Boring Notch Contribution")
        XCTAssertEqual(notice.status, .needsAction(.permission))
        XCTAssertEqual(notice.status.title, "Permission Required")
        XCTAssertEqual(notice.resultSummary, "May I build the Debug app for visual verification?")
        XCTAssertEqual(
            notice.permissionDetails,
            CodexPermissionDetails(
                toolName: "Bash",
                description: "May I build the Debug app for visual verification?",
                command: "xcodebuild -scheme boringNotch build",
                additionalInput: """
                {
                  "sandbox_permissions" : "require_escalated"
                }
                """
            )
        )
        XCTAssertEqual(notice.permissionCallback, permissionCallback)
    }

    func testParsesBrowserPermissionRequestAsActionableNotification() throws {
        var state = CodexNotificationState()
        state.reduce(try parsePermissionPayload(#"""
        {
            "hook_event_name":"PermissionRequest",
            "session_id":"browser-session",
            "turn_id":"browser-turn",
            "cwd":"/tmp/browser-project",
            "tool_name":"Browser",
            "tool_input":{
                "description":"Open the documentation page in Browser",
                "url":"https://example.com/docs"
            },
            "boring_notch_approval":{
                "port":49152,
                "token":"abcdefghijklmnopqrstuvwxyzABCDEF",
                "expires_at":4102444800
            }
        }
        """#))

        let notice = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(notice.status, .needsAction(.permission))
        XCTAssertEqual(notice.status.title, "Permission Required")
        XCTAssertEqual(notice.permissionDetails?.toolName, "Browser")
        XCTAssertEqual(
            notice.permissionDetails?.description,
            "Open the documentation page in Browser"
        )
        XCTAssertEqual(
            notice.permissionDetails?.additionalInput,
            """
            {
              "url" : "https:\\/\\/example.com\\/docs"
            }
            """
        )
        XCTAssertEqual(notice.permissionCallback, permissionCallback)
    }

    func testPermissionRequestCarriesAutomaticReviewerMode() throws {
        let event = try parsePermissionPayload(#"""
        {
            "hook_event_name":"PermissionRequest",
            "session_id":"auto-reviewed",
            "tool_name":"Bash",
            "tool_input":{"command":"xcodebuild -scheme boringNotch build"},
            "boring_notch_approval":{
                "port":49152,
                "token":"abcdefghijklmnopqrstuvwxyzABCDEF",
                "expires_at":4102444800
            },
            "boring_notch_approval_reviewer":"auto_review"
        }
        """#)

        guard case .permissionRequest(_, _, _, _, let details, _, _, _) = event else {
            return XCTFail("Expected a permission request")
        }
        XCTAssertTrue(details.isAutoReviewed)

        var state = CodexNotificationState()
        state.reduce(event)
        XCTAssertTrue(state.notifications.isEmpty)
        XCTAssertNil(state.visibleNotification())
    }

    func testUserReviewedPermissionIsPresentedImmediately() throws {
        var state = CodexNotificationState()
        state.reduce(try parsePermissionPayload(#"""
        {
            "hook_event_name":"PermissionRequest",
            "session_id":"user-reviewed",
            "turn_id":"turn-1",
            "tool_name":"Bash",
            "tool_input":{"command":"xcodebuild -scheme boringNotch build"},
            "boring_notch_approval":{
                "port":49152,
                "token":"abcdefghijklmnopqrstuvwxyzABCDEF",
                "expires_at":4102444800
            },
            "boring_notch_approval_reviewer":"user"
        }
        """#))

        let pending = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(pending.permissionCallback, permissionCallback)
    }

    func testProjectlessPermissionUsesChatMetadataAndPlaceholder() throws {
        var state = CodexNotificationState()
        state.reduce(try parsePermissionPayload(#"""
        {
            "hook_event_name":"PermissionRequest",
            "session_id":"projectless-session",
            "turn_id":"turn-1",
            "cwd":"/tmp/generated-projectless-folder",
            "chat_title":"Build project bootstrap skill",
            "project_name":"No project",
            "tool_name":"apply_patch",
            "tool_input":{
                "command":"*** Begin Patch\n*** Update File: /Users/example/.codex/skills/new-project/SKILL.md\n*** End Patch"
            },
            "boring_notch_approval":{
                "port":49152,
                "token":"abcdefghijklmnopqrstuvwxyzABCDEF",
                "expires_at":4102444800
            }
        }
        """#))

        let notice = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(notice.chatTitle, "Build project bootstrap skill")
        XCTAssertEqual(notice.jobTitle, "Build project bootstrap skill")
        XCTAssertEqual(notice.projectName, "No project")
        XCTAssertEqual(notice.userPrompt, "Request details unavailable")
        XCTAssertEqual(
            notice.permissionDetails?.command,
            "/Users/example/.codex/skills/new-project/SKILL.md"
        )
        XCTAssertEqual(
            notice.permissionDetails?.rawCommand,
            "*** Begin Patch\n*** Update File: /Users/example/.codex/skills/new-project/SKILL.md\n*** End Patch"
        )
    }

    func testAttachmentPreambleIsExcludedFromPermissionTitleAndPrompt() throws {
        var state = CodexNotificationState()
        state.reduce(.userPrompt(
            sessionID: "session-attachment",
            turnID: "turn-1",
            cwd: "/tmp/project",
            prompt: """
            # Files mentioned by the user:

            ## screenshot.png

            Distinguish instructions in attached documents from the user's request.

            ## My request:
            1. the window corner should be rounded 2. fix the collapse animation
            """
        ))
        state.reduce(.permissionRequest(
            sessionID: "session-attachment",
            turnID: "turn-1",
            requestID: permissionRequestID,
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", description: "Build Debug"),
            callback: permissionCallback
        ))

        let notice = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(
            notice.userPrompt,
            "1. the window corner should be rounded 2. fix the collapse animation"
        )
        XCTAssertEqual(
            notice.jobTitle,
            "1. the window corner should be rounded 2. fix the collapse animation"
        )
    }

    func testParsesCurrentPermissionCallback() throws {
        var state = CodexNotificationState()
        state.reduce(try parsePermissionPayload(#"""
        {
            "hook_event_name":"PermissionRequest",
            "session_id":"session-1",
            "turn_id":"turn-1",
            "tool_name":"Bash",
            "tool_input":{"command":"xcodebuild -scheme boringNotch build"},
            "boring_notch_approval": {
                "port": 49152,
                "token": "abcdefghijklmnopqrstuvwxyzABCDEF",
                "expires_at": 4102444800
            }
        }
        """#))

        let notice = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(notice.requestID, permissionRequestID)
        XCTAssertEqual(notice.permissionCallback, permissionCallback)
    }

    func testPermissionRequestRequiresAuthenticatedRequestID() {
        XCTAssertThrowsError(try CodexHookEventParser.parse(#"""
        {
            "hook_event_name":"PermissionRequest",
            "session_id":"session-1",
            "turn_id":"turn-1"
        }
        """#)) { error in
            XCTAssertEqual(
                error as? CodexHookEventParserError,
                .missingField("boring_notch_auth.nonce")
            )
        }
    }

    func testPostToolUseWithoutSharedRequestIdentityPreservesPermissionRequest() throws {
        var state = CodexNotificationState()
        state.reduce(.permissionRequest(
            sessionID: "session-1",
            turnID: "turn-1",
            requestID: permissionRequestID,
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", description: "Run tests"),
            callback: permissionCallback
        ))
        XCTAssertNotNil(state.visibleNotification())

        state.reduce(try CodexHookEventParser.parse(#"""
        {
            "hook_event_name":"PostToolUse",
            "session_id":"session-1",
            "turn_id":"turn-1",
            "cwd":"/tmp/project"
        }
        """#))

        XCTAssertNotNil(state.visibleNotification())
    }

    func testConcurrentSameTurnPermissionRequestsRemainIndependentlyActionable() throws {
        var state = CodexNotificationState()
        let firstCallback = permissionCallback
        let secondCallback = CodexPermissionCallback(
            port: 49_153,
            token: "0123456789abcdef0123456789abcdef",
            expiresAt: permissionCallback.expiresAt
        )
        state.reduce(.permissionRequest(
            sessionID: "shared-session",
            turnID: "shared-turn",
            requestID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", command: "first"),
            callback: firstCallback
        ))
        state.reduce(.permissionRequest(
            sessionID: "shared-session",
            turnID: "shared-turn",
            requestID: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", command: "second"),
            callback: secondCallback
        ))

        XCTAssertEqual(state.notifications.count, 2)
        XCTAssertTrue(state.notifications.contains { $0.permissionCallback == firstCallback })
        XCTAssertTrue(state.notifications.contains { $0.permissionCallback == secondCallback })

        let chosen = try XCTUnwrap(
            state.notifications.first { $0.permissionCallback == firstCallback }
        )
        state.dismiss(chosen.id)

        XCTAssertEqual(state.notifications.count, 1)
        XCTAssertEqual(state.notifications.first?.permissionCallback, secondCallback)
    }

    func testStopClearsEveryOutstandingPermissionForTheCompletedTurn() {
        var state = CodexNotificationState()
        for requestID in [
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        ] {
            state.reduce(.permissionRequest(
                sessionID: "shared-session",
                turnID: "shared-turn",
                requestID: requestID,
                cwd: "/tmp/project",
                details: CodexPermissionDetails(toolName: "Bash", command: requestID),
                callback: permissionCallback
            ))
        }

        state.reduce(.stop(
            sessionID: "shared-session",
            turnID: "shared-turn",
            cwd: "/tmp/project",
            result: "Completed successfully.",
            reportedStatus: "succeeded"
        ))

        XCTAssertEqual(state.notifications.count, 1)
        XCTAssertEqual(state.notifications.first?.status, .succeeded)
    }

    func testPermissionRequestWithoutUsableCallbackIsNotPresented() throws {
        let payloads = [
            #"{"hook_event_name":"PermissionRequest","session_id":"absent"}"#,
            #"{"hook_event_name":"PermissionRequest","session_id":"missing-callback","boring_notch_approval":{}}"#,
            #"{"hook_event_name":"PermissionRequest","session_id":"low-port","boring_notch_approval":{"port":1023,"token":"abcdefghijklmnopqrstuvwxyzABCDEF","expires_at":4102444800}}"#,
            #"{"hook_event_name":"PermissionRequest","session_id":"high-port","boring_notch_approval":{"port":65536,"token":"abcdefghijklmnopqrstuvwxyzABCDEF","expires_at":4102444800}}"#,
            #"{"hook_event_name":"PermissionRequest","session_id":"short-token","boring_notch_approval":{"port":49152,"token":"short","expires_at":4102444800}}"#,
            #"{"hook_event_name":"PermissionRequest","session_id":"invalid-token","boring_notch_approval":{"port":49152,"token":"abcdefghijklmnopqrstuvwxyzABCDE!","expires_at":4102444800}}"#,
            #"{"hook_event_name":"PermissionRequest","session_id":"missing-expiry","boring_notch_approval":{"port":49152,"token":"abcdefghijklmnopqrstuvwxyzABCDEF"}}"#
        ]

        for payload in payloads {
            var state = CodexNotificationState()
            state.reduce(try parsePermissionPayload(payload))
            let notice = try XCTUnwrap(state.notifications.first, payload)
            XCTAssertEqual(notice.status, .needsAction(.permission), payload)
            XCTAssertNil(notice.permissionCallback, payload)
            XCTAssertNil(state.visibleNotification(), payload)
        }
    }

    func testExpiredPermissionCallbackIsNotPresented() throws {
        var state = CodexNotificationState()
        state.reduce(try parsePermissionPayload(#"""
        {
            "hook_event_name":"PermissionRequest",
            "session_id":"expired",
            "boring_notch_approval":{
                "port":49152,
                "token":"abcdefghijklmnopqrstuvwxyzABCDEF",
                "expires_at":99
            }
        }
        """#), at: Date(timeIntervalSince1970: 100))

        XCTAssertNotNil(state.notifications.first)
        XCTAssertNil(state.visibleNotification(at: Date(timeIntervalSince1970: 100)))
    }

    func testExpiryRemovesOnlyTheExpiredSameTurnPermissionRequest() throws {
        var state = CodexNotificationState()
        let expiredCallback = CodexPermissionCallback(
            port: 49_152,
            token: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            expiresAt: Date(timeIntervalSince1970: 100)
        )
        let liveCallback = CodexPermissionCallback(
            port: 49_153,
            token: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            expiresAt: Date(timeIntervalSince1970: 200)
        )
        state.reduce(.permissionRequest(
            sessionID: "shared-session",
            turnID: "shared-turn",
            requestID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", command: "expired"),
            callback: expiredCallback
        ))
        state.reduce(.permissionRequest(
            sessionID: "shared-session",
            turnID: "shared-turn",
            requestID: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", command: "live"),
            callback: liveCallback
        ))

        state.removeExpiredPermissionRequests(at: Date(timeIntervalSince1970: 150))

        XCTAssertEqual(state.notifications.count, 1)
        let remaining = try XCTUnwrap(state.notifications.first)
        XCTAssertEqual(remaining.requestID, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        XCTAssertEqual(remaining.permissionCallback, liveCallback)
    }

    func testStopReplacesPermissionWithVerifiedSuccess() throws {
        var state = CodexNotificationState()
        state.reduce(.userPrompt(
            sessionID: "session-1",
            turnID: "turn-1",
            cwd: "/tmp/project",
            prompt: "Build the app"
        ))
        state.reduce(.permissionRequest(
            sessionID: "session-1",
            turnID: "turn-1",
            requestID: permissionRequestID,
            cwd: "/tmp/project",
            details: CodexPermissionDetails(
                toolName: "Bash",
                description: "Run xcodebuild"
            ),
            callback: permissionCallback
        ))
        let completedAt = Date(timeIntervalSince1970: 100)
        state.reduce(.stop(
            sessionID: "session-1",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "Build succeeded. All 12 tests passed."
        ), at: completedAt)

        XCTAssertEqual(state.notifications.count, 1)
        let notice = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(notice.status, .succeeded)
    }

    func testInterruptedStopIsClassifiedAsFailure() throws {
        var state = CodexNotificationState()
        state.reduce(try CodexHookEventParser.parse(#"""
        {
            "hook_event_name":"Stop",
            "session_id":"session-interrupted",
            "turn_id":"turn-1",
            "cwd":"/tmp/project",
            "last_assistant_message":"Codex task was interrupted before completion."
        }
        """#), at: Date(timeIntervalSince1970: 100))

        let notice = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(notice.status, .failed)
        XCTAssertEqual(notice.resultSummary, "Codex task was interrupted before completion.")
    }

    func testStopWithoutAssistantMessageIsClassifiedAsFailure() throws {
        var state = CodexNotificationState()
        state.reduce(try CodexHookEventParser.parse(#"""
        {
            "hook_event_name":"Stop",
            "session_id":"session-empty-stop",
            "turn_id":"turn-1",
            "cwd":"/tmp/project"
        }
        """#), at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(
            state.visibleNotification()?.status,
            .failed
        )
    }

    func testOnlyPermissionRemindersPersist() {
        var state = CodexNotificationState()
        let now = Date(timeIntervalSince1970: 20)
        state.reduce(.stop(
            sessionID: "session-1",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "The build failed because the helper target could not link."
        ), at: now)

        let notice = state.visibleNotification()
        XCTAssertEqual(notice?.status, .failed)

        XCTAssertTrue(CodexJobStatus.needsAction(.permission).isPersistent)
        XCTAssertFalse(CodexJobStatus.needsAction(.decision).isPersistent)
        XCTAssertFalse(CodexJobStatus.needsAction(.manualCheck).isPersistent)
        XCTAssertFalse(CodexJobStatus.failed.isPersistent)
        XCTAssertFalse(CodexJobStatus.succeeded.isPersistent)
        XCTAssertEqual(CodexJobStatus.failed.title, "Failure")
        XCTAssertEqual(CodexJobStatus.succeeded.title, "Success")
    }

    func testStopKeepsFullPromptForExpandedViewAndUsesProjectContext() throws {
        var state = CodexNotificationState()
        let prompt = String(repeating: "Inspect this project carefully. ", count: 8)
        state.reduce(.userPrompt(
            sessionID: "session-1",
            turnID: "turn-1",
            cwd: "/tmp/boring.notch",
            prompt: prompt
        ))
        state.reduce(.stop(
            sessionID: "session-1",
            turnID: "turn-1",
            cwd: "/tmp/boring.notch",
            result: "Build succeeded."
        ))

        let notice = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(notice.userPrompt, prompt)
        XCTAssertEqual(notice.projectName, "boring.notch")
        XCTAssertLessThan(notice.jobTitle.count, prompt.count)
        XCTAssertTrue(notice.jobTitle.hasSuffix("..."))
    }

    func testEventFromNewTurnDoesNotReusePreviousTurnPromptContext() throws {
        var state = CodexNotificationState()
        state.reduce(.userPrompt(
            sessionID: "session-1",
            turnID: "turn-1",
            cwd: "/tmp/first-project",
            prompt: "Only belongs to the first turn"
        ))

        state.reduce(.stop(
            sessionID: "session-1",
            turnID: "turn-2",
            cwd: "/tmp/second-project",
            result: "Second turn completed successfully."
        ))

        let notice = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(notice.turnID, "turn-2")
        XCTAssertEqual(notice.jobTitle, "Codex · second-project")
        XCTAssertEqual(notice.chatTitle, "Codex · second-project")
        XCTAssertEqual(notice.userPrompt, "Request details unavailable")
        XCTAssertEqual(notice.projectName, "second-project")
    }

    func testManualVerificationAndDecisionAreActionable() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "manual",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "Implementation is complete. Please verify the animation manually in Debug."
        ), at: Date(timeIntervalSince1970: 10))
        state.reduce(.stop(
            sessionID: "decision",
            turnID: "turn-2",
            cwd: "/tmp/project",
            result: "I need your decision: should the alert stay until dismissed or expire?"
        ), at: Date(timeIntervalSince1970: 11))
        state.reduce(.stop(
            sessionID: "success",
            turnID: "turn-3",
            cwd: "/tmp/project",
            result: "Finished preparing the stand-up summary."
        ), at: Date(timeIntervalSince1970: 12))

        XCTAssertEqual(
            state.notifications.first { $0.sessionID == "manual" }?.status,
            .needsAction(.manualCheck)
        )
        XCTAssertEqual(
            state.notifications.first { $0.sessionID == "decision" }?.status,
            .needsAction(.decision)
        )
        XCTAssertEqual(
            state.notifications.first { $0.sessionID == "success" }?.status,
            .succeeded
        )
    }

    func testDecisionMessageOutranksReportedSuccessStatus() throws {
        var state = CodexNotificationState()
        state.reduce(try CodexHookEventParser.parse(#"""
        {
            "hook_event_name":"Stop",
            "session_id":"decision-reported-success",
            "turn_id":"turn-1",
            "last_assistant_message":"The work is ready. Please choose which option I should apply next.",
            "status":"succeeded"
        }
        """#))

        XCTAssertEqual(
            state.visibleNotification()?.status,
            .needsAction(.decision)
        )

        state.reduce(try CodexHookEventParser.parse(#"""
        {
            "hook_event_name":"Stop",
            "session_id":"decision-question",
            "turn_id":"turn-2",
            "last_assistant_message":"Both approaches are ready. Which approach should I take?",
            "status":"success"
        }
        """#))

        XCTAssertEqual(
            state.notifications.first { $0.sessionID == "decision-question" }?.status,
            .needsAction(.decision)
        )
    }

    func testDecisionResponseWithExplicitAOrBChoiceIsActionable() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "decision-a-or-b",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: """
            A. Minimal targeted change — faster and lower risk.
            B. Broader modular refactor — more extensible but higher risk.
            Choose A or B.
            """,
            reportedStatus: "succeeded"
        ))

        XCTAssertEqual(
            state.visibleNotification()?.status,
            .needsAction(.decision)
        )
    }

    func testManualReviewResponseIsActionable() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "manual-review",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: """
            Proposed action: review the untracked directory before adding it.
            Risks: it may contain generated files or unrelated work.
            Please manually review this recommendation and approve or reject proceeding.
            """,
            reportedStatus: "succeeded"
        ))

        XCTAssertEqual(
            state.visibleNotification()?.status,
            .needsAction(.manualCheck)
        )
    }

    func testSuccessfulReportMentioningManualTestReferenceRemainsSuccess() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "successful-report",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: """
            Done.
            Updated the manual test reference in AGENT.md.
            Verified 35 tests pass and the Debug build succeeds.
            """,
            reportedStatus: "succeeded"
        ))

        XCTAssertEqual(
            state.visibleNotification()?.status,
            .succeeded
        )
    }

    func testProductionStopSummaryWithPastFailureRemainsSuccess() throws {
        // The Codex Stop hook wire schema has no status field, so production
        // classification must rely on the assistant message alone.
        for message in [
            "Fixed the command failed regression. All tests passed.",
            "Fixed the issue where the command failed. All tests passed.",
            "The command failed initially; after fixing it, all tests passed.",
        ] {
            XCTAssertEqual(
                try productionStopStatus(message),
                .succeeded,
                message
            )
        }
    }

    func testProductionStopKeepsAffirmativeFailuresDespiteLaterSuccessText() throws {
        for message in [
            "Tests failed, although the build succeeded.",
            "The command failed. Not all tests passed.",
            "Earlier tests failed and remain unresolved.",
            "Addressed command failed again.",
            "Fixed lint but the command failed. All tests passed.",
            "The command failed and was not fixed. All tests passed.",
            "Fixed the issue where the command failed. Tests are still failing.",
            "The command failed initially; after fixing it, not all tests passed.",
        ] {
            XCTAssertEqual(
                try productionStopStatus(message),
                .failed,
                message
            )
        }
    }

    func testProductionStopTreatsNegativeOutcomesAsFailures() throws {
        for message in [
            "Not all tests passed.",
            "The build did not succeed.",
            "Tests are still failing.",
        ] {
            XCTAssertEqual(
                try productionStopStatus(message),
                .failed,
                message
            )
        }
    }

    func testNegatedManualReviewDoesNotOverrideReportedSuccess() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "negated-manual-review",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "All checks passed. No manual review required.",
            reportedStatus: "succeeded"
        ))

        XCTAssertEqual(state.visibleNotification()?.status, .succeeded)
    }

    func testNegatedDecisionRequestDoesNotOverrideReportedSuccess() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "negated-decision",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "All checks passed; I do not think I need your input.",
            reportedStatus: "succeeded"
        ))

        XCTAssertEqual(state.visibleNotification()?.status, .succeeded)
    }

    func testAffirmativeChoiceAfterNegatedClauseRemainsActionable() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "affirmative-after-negation",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "I do not need more context, but please choose A or B.",
            reportedStatus: "succeeded"
        ))

        XCTAssertEqual(state.visibleNotification()?.status, .needsAction(.decision))
    }

    func testAffirmativeInputRequestAfterCoordinatedNegatedClauseIsActionable() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "coordinated-negation",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "I did not change the API and I need your input.",
            reportedStatus: "succeeded"
        ))

        XCTAssertEqual(state.visibleNotification()?.status, .needsAction(.decision))
    }

    func testAffirmativeInputRequestAfterCoordinatedPredicateIsActionable() throws {
        for coordinator in ["", "still ", "also ", "now "] {
            XCTAssertEqual(
                try productionStopStatus(
                    "I did not change the API and \(coordinator)need your input."
                ),
                .needsAction(.decision),
                "The affirmative clause after 'and \(coordinator)' must not inherit the earlier negation."
            )
        }
    }

    func testAffirmativeInputRequestAfterCausalNegatedClauseIsActionable() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "causal-negation",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "Tests did not run because I need your input.",
            reportedStatus: "succeeded"
        ))

        XCTAssertEqual(state.visibleNotification()?.status, .needsAction(.decision))
    }

    func testProductionStopFindsRequestsInAffirmativeSubordinateClauses() throws {
        for conjunction in ["although", "since", "while", "whereas", "even though"] {
            let message = "I did not change the API \(conjunction) I need your input."
            XCTAssertEqual(
                try productionStopStatus(message),
                .needsAction(.decision),
                message
            )
        }
    }

    func testNotOnlyDoesNotNegateAnAffirmativeInputRequest() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "not-only",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "I do not only need your input; I also need your decision.",
            reportedStatus: "succeeded"
        ))

        XCTAssertEqual(state.visibleNotification()?.status, .needsAction(.decision))
    }

    func testCoordinatedVerbsRemainInsideNegationScope() throws {
        for result in [
            "I do not need to build and manually verify this.",
            "I do not need to build and also manually verify this.",
            "I do not need to build the application locally and manually verify this.",
        ] {
            XCTAssertEqual(try productionStopStatus(result), .succeeded)
        }
    }

    func testLaterFailureOutranksEarlierSuccessWithoutReportedStatus() throws {
        XCTAssertEqual(
            try productionStopStatus("All tests passed, but the command failed."),
            .failed
        )
    }

    func testFailureResponseWithStatusTextIsFailed() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "diagnostic-failure",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: """
            Command: cat /dev/null/codex-diagnostic-file
            Error: Not a directory
            Status: failed (exit code 1).
            """
        ))

        XCTAssertEqual(
            state.visibleNotification()?.status,
            .failed
        )
    }

    func testPassiveNotificationCanStartItsDwellAfterPresentation() {
        var state = CodexNotificationState()
        let completedAt = Date(timeIntervalSince1970: 100)
        state.reduce(.stop(
            sessionID: "session-1",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "Build succeeded."
        ), at: completedAt)

        XCTAssertNotNil(state.visibleNotification())
        XCTAssertEqual(CodexNotificationTiming.passiveDwellDuration, 3)
    }

    func testNewArrivalDuringPassiveFadeCannotResurfaceConsumedNotification() throws {
        var state = CodexNotificationState()
        var policy = CodexPassivePresentationPolicy()
        state.reduce(.stop(
            sessionID: "consumed-session",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "First task failed.",
            reportedStatus: "failed"
        ), at: Date(timeIntervalSince1970: 10))
        let consumed = try XCTUnwrap(state.visibleNotification())

        policy.consumeBeforeFade(
            CodexNotificationPresentationToken(consumed),
            from: &state
        )
        state.reduce(.stop(
            sessionID: "new-session",
            turnID: "turn-2",
            cwd: "/tmp/project",
            result: "Second task completed successfully.",
            reportedStatus: "succeeded"
        ), at: Date(timeIntervalSince1970: 20))

        let newNotification = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(newNotification.sessionID, "new-session")
        state.dismiss(newNotification.id)
        XCTAssertNil(state.visibleNotification())
        XCTAssertFalse(state.notifications.contains { $0.id == consumed.id })
    }

    func testCompactLaunchFailureRetainsOnlyTheMatchingNotificationForRetry() throws {
        var state = CodexNotificationState()
        var policy = CodexPassivePresentationPolicy()
        state.reduce(.stop(
            sessionID: "failed-launch",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "Task completed successfully.",
            reportedStatus: "succeeded"
        ), at: Date(timeIntervalSince1970: 10))
        let notification = try XCTUnwrap(state.visibleNotification())
        let token = CodexNotificationPresentationToken(notification)

        XCTAssertTrue(policy.beginCompactLaunch(for: token))
        XCTAssertTrue(policy.preventsAutomaticDismissal(of: token))
        policy.recordCompactLaunchFailure("Codex could not be opened.", for: token)

        XCTAssertTrue(policy.preventsAutomaticDismissal(of: token))
        XCTAssertEqual(
            policy.compactLaunchError(for: token),
            "Codex could not be opened."
        )
        XCTAssertTrue(policy.beginCompactLaunch(for: token), "A failed launch must be retryable")
        policy.recordCompactLaunchSuccess(for: token)
        XCTAssertFalse(policy.preventsAutomaticDismissal(of: token))
        XCTAssertNil(policy.compactLaunchError(for: token))
    }

    func testOverlappingCompactLaunchSuccessesDismissIndependentlyWithoutResurfacing() throws {
        var state = CodexNotificationState()
        var policy = CodexPassivePresentationPolicy()
        state.reduce(.stop(
            sessionID: "first-launch",
            turnID: "turn-1",
            cwd: "/tmp/first-project",
            result: "First task completed successfully.",
            reportedStatus: "succeeded"
        ), at: Date(timeIntervalSince1970: 10))
        let firstNotification = try XCTUnwrap(state.visibleNotification())
        state.reduce(.stop(
            sessionID: "second-launch",
            turnID: "turn-2",
            cwd: "/tmp/second-project",
            result: "Second task completed successfully.",
            reportedStatus: "succeeded"
        ), at: Date(timeIntervalSince1970: 20))
        let secondNotification = try XCTUnwrap(state.visibleNotification())
        let firstToken = CodexNotificationPresentationToken(firstNotification)
        let secondToken = CodexNotificationPresentationToken(secondNotification)

        XCTAssertTrue(policy.beginCompactLaunch(for: firstToken))
        XCTAssertTrue(policy.beginCompactLaunch(for: secondToken))

        XCTAssertTrue(policy.preventsAutomaticDismissal(of: firstToken))
        if policy.preventsAutomaticDismissal(of: firstToken) {
            policy.recordCompactLaunchSuccess(for: firstToken)
            state.dismiss(firstToken)
        }
        XCTAssertEqual(state.visibleNotification()?.id, secondNotification.id)

        XCTAssertTrue(policy.preventsAutomaticDismissal(of: secondToken))
        policy.recordCompactLaunchSuccess(for: secondToken)
        state.dismiss(secondToken)

        XCTAssertNil(state.visibleNotification())
    }

    func testOverlappingCompactLaunchFailureResurfacesWithIndependentRetryState() throws {
        var state = CodexNotificationState()
        var policy = CodexPassivePresentationPolicy()
        state.reduce(.stop(
            sessionID: "first-launch",
            turnID: "turn-1",
            cwd: "/tmp/first-project",
            result: "First task completed successfully.",
            reportedStatus: "succeeded"
        ), at: Date(timeIntervalSince1970: 10))
        let firstNotification = try XCTUnwrap(state.visibleNotification())
        state.reduce(.stop(
            sessionID: "second-launch",
            turnID: "turn-2",
            cwd: "/tmp/second-project",
            result: "Second task completed successfully.",
            reportedStatus: "succeeded"
        ), at: Date(timeIntervalSince1970: 20))
        let secondNotification = try XCTUnwrap(state.visibleNotification())
        let firstToken = CodexNotificationPresentationToken(firstNotification)
        let secondToken = CodexNotificationPresentationToken(secondNotification)
        let launchError = "Codex could not be opened."

        XCTAssertTrue(policy.beginCompactLaunch(for: firstToken))
        XCTAssertTrue(policy.beginCompactLaunch(for: secondToken))

        XCTAssertTrue(policy.preventsAutomaticDismissal(of: firstToken))
        policy.recordCompactLaunchFailure(launchError, for: firstToken)
        XCTAssertEqual(policy.compactLaunchError(for: firstToken), launchError)

        XCTAssertTrue(policy.preventsAutomaticDismissal(of: secondToken))
        policy.recordCompactLaunchSuccess(for: secondToken)
        state.dismiss(secondToken)

        let resurfacedNotification = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(resurfacedNotification.id, firstNotification.id)
        XCTAssertEqual(
            policy.compactLaunchError(
                for: CodexNotificationPresentationToken(resurfacedNotification)
            ),
            launchError
        )
        XCTAssertTrue(policy.beginCompactLaunch(for: firstToken))
        policy.recordCompactLaunchSuccess(for: firstToken)
        state.dismiss(firstToken)

        XCTAssertNil(state.visibleNotification())
    }

    func testHiddenCompactLaunchFailureKeepsNewerPassivePresentationTimer() {
        let firstNotification = CodexJobNotification(
            id: "first-launch",
            sessionID: "first-launch",
            turnID: "turn-1",
            requestID: nil,
            jobTitle: "First launch",
            resultSummary: "Completed",
            status: .succeeded,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let secondNotification = CodexJobNotification(
            id: "second-launch",
            sessionID: "second-launch",
            turnID: "turn-2",
            requestID: nil,
            jobTitle: "Second launch",
            resultSummary: "Completed",
            status: .succeeded,
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let firstToken = CodexNotificationPresentationToken(firstNotification)
        let secondToken = CodexNotificationPresentationToken(secondNotification)
        var policy = CodexPassivePresentationPolicy()
        var passiveTimerOwner: CodexNotificationPresentationToken? = secondToken

        XCTAssertTrue(policy.beginCompactLaunch(for: firstToken))
        policy.recordCompactLaunchFailure(
            "Codex could not be opened.",
            for: firstToken
        )
        if policy.shouldCancelPassiveDismissalTask(
            for: firstToken,
            activePresentationToken: passiveTimerOwner
        ) {
            passiveTimerOwner = nil
        }

        XCTAssertEqual(passiveTimerOwner, secondToken)
        XCTAssertTrue(policy.shouldCancelPassiveDismissalTask(
            for: firstToken,
            activePresentationToken: firstToken
        ))
    }

    func testPromptTransitionDurationUsesTheConfiguredAnimationResponse() {
        XCTAssertEqual(
            CodexNotificationTiming.transitionDuration(
                animationSpeedMultiplier: 1,
                animationsEnabled: true
            ),
            0.42,
            accuracy: 0.001
        )
        XCTAssertEqual(
            CodexNotificationTiming.transitionDuration(
                animationSpeedMultiplier: 1,
                animationsEnabled: false
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(CodexNotificationTiming.passiveDwellDuration, 3)
    }

    func testCodexPermissionHoverExpansionUsesLongerBoundary() {
        XCTAssertEqual(
            CodexNotificationTiming.codexHoverExpansionDelay,
            0.6,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(
            CodexNotificationTiming.codexHoverExpansionDelay,
            0.3
        )
    }

    func testPassiveDismissalTracksHoverPerNotchSurface() {
        var surfaces = CodexNotificationPresentationSurfaces()
        surfaces.begin(surfaceID: "display-1")
        surfaces.begin(surfaceID: "display-2")

        surfaces.setHovered(true, surfaceID: "display-1")
        XCTAssertTrue(surfaces.isPassiveDismissalPaused)

        surfaces.setHovered(false, surfaceID: "display-2")
        XCTAssertTrue(surfaces.isPassiveDismissalPaused)

        surfaces.setHovered(false, surfaceID: "display-1")
        XCTAssertFalse(surfaces.isPassiveDismissalPaused)
    }

    func testEndingOneNotchSurfaceDoesNotClearAnotherHoveredSurface() {
        var surfaces = CodexNotificationPresentationSurfaces()
        surfaces.begin(surfaceID: "display-1")
        surfaces.begin(surfaceID: "display-2")
        surfaces.setHovered(true, surfaceID: "display-2")

        surfaces.end(surfaceID: "display-1")

        XCTAssertTrue(surfaces.isPassiveDismissalPaused)
        XCTAssertEqual(surfaces.activeSurfaceIDs, ["display-2"])
    }

    func testActionRequiredOutranksNewerCompletion() throws {
        var state = CodexNotificationState()
        state.reduce(.permissionRequest(
            sessionID: "permission",
            turnID: "turn-1",
            requestID: permissionRequestID,
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", description: "Run tests"),
            callback: permissionCallback
        ), at: Date(timeIntervalSince1970: 10))
        state.reduce(.stop(
            sessionID: "complete",
            turnID: "turn-2",
            cwd: "/tmp/other",
            result: "Finished preparing the report."
        ), at: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(state.visibleNotification()?.sessionID, "permission")
    }

    func testNotificationCapPreservesLivePermissionRequests() {
        var state = CodexNotificationState()
        let callback = CodexPermissionCallback(
            port: 49_152,
            token: "abcdefghijklmnopqrstuvwxyzABCDEF",
            expiresAt: Date(timeIntervalSince1970: 100)
        )
        state.reduce(.permissionRequest(
            sessionID: "permission",
            turnID: "permission-turn",
            requestID: permissionRequestID,
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", description: "Run tests"),
            callback: callback
        ), at: Date(timeIntervalSince1970: 1))

        for index in 1...20 {
            state.reduce(.stop(
                sessionID: "completed-\(index)",
                turnID: "turn-\(index)",
                cwd: "/tmp/project",
                result: "Completed successfully.",
                reportedStatus: "succeeded"
            ), at: Date(timeIntervalSince1970: TimeInterval(index + 1)))
        }

        XCTAssertEqual(state.notifications.count, 20)
        XCTAssertTrue(state.notifications.contains { $0.sessionID == "permission" })
    }

    func testNotificationCapAllowsOverflowWhenEveryNotificationIsALivePermission() {
        var state = CodexNotificationState()
        let callback = CodexPermissionCallback(
            port: 49_152,
            token: "abcdefghijklmnopqrstuvwxyzABCDEF",
            expiresAt: Date(timeIntervalSince1970: 100)
        )

        for index in 1...21 {
            state.reduce(.permissionRequest(
                sessionID: "permission-\(index)",
                turnID: "turn-\(index)",
                requestID: String(format: "%032x", index),
                cwd: "/tmp/project",
                details: CodexPermissionDetails(toolName: "Bash", description: "Run tests"),
                callback: callback
            ), at: Date(timeIntervalSince1970: TimeInterval(index)))
        }

        XCTAssertEqual(state.notifications.count, 21)
    }

    func testPromptContextsAreBoundedToRecentSessions() throws {
        var state = CodexNotificationState()
        for index in 1...21 {
            state.reduce(.userPrompt(
                sessionID: "session-\(index)",
                turnID: "turn-\(index)",
                cwd: "/tmp/project-\(index)",
                prompt: "Prompt \(index)"
            ))
        }

        state.reduce(.permissionRequest(
            sessionID: "session-1",
            turnID: "turn-1",
            requestID: "11111111111111111111111111111111",
            cwd: "/tmp/project-1",
            details: CodexPermissionDetails(toolName: "Bash", description: "Old request"),
            callback: permissionCallback
        ))
        state.reduce(.permissionRequest(
            sessionID: "session-21",
            turnID: "turn-21",
            requestID: "21212121212121212121212121212121",
            cwd: "/tmp/project-21",
            details: CodexPermissionDetails(toolName: "Bash", description: "Recent request"),
            callback: permissionCallback
        ))

        let oldNotification = try XCTUnwrap(
            state.notifications.first { $0.sessionID == "session-1" }
        )
        let recentNotification = try XCTUnwrap(
            state.notifications.first { $0.sessionID == "session-21" }
        )
        XCTAssertEqual(oldNotification.userPrompt, "Request details unavailable")
        XCTAssertEqual(recentNotification.userPrompt, "Prompt 21")
    }

    func testSameTurnPermissionAndStopRetainPromptCorrelation() throws {
        var state = CodexNotificationState()
        state.reduce(.userPrompt(
            sessionID: "correlated-session",
            turnID: "correlated-turn",
            cwd: "/tmp/project",
            prompt: "Keep this prompt through the terminal event"
        ))
        for index in 2...20 {
            state.reduce(.userPrompt(
                sessionID: "session-\(index)",
                turnID: "turn-\(index)",
                cwd: "/tmp/project-\(index)",
                prompt: "Prompt \(index)"
            ))
        }
        state.reduce(.permissionRequest(
            sessionID: "correlated-session",
            turnID: "correlated-turn",
            requestID: permissionRequestID,
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", description: "Run tests"),
            callback: permissionCallback
        ))
        state.reduce(.userPrompt(
            sessionID: "session-21",
            turnID: "turn-21",
            cwd: "/tmp/project-21",
            prompt: "Prompt 21"
        ))
        state.reduce(.stop(
            sessionID: "correlated-session",
            turnID: "correlated-turn",
            cwd: "/tmp/project",
            result: "Completed successfully.",
            reportedStatus: "succeeded"
        ))

        let notification = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(notification.userPrompt, "Keep this prompt through the terminal event")
        XCTAssertEqual(notification.status, .succeeded)
    }

    func testPermissionCallbackPersistsUntilDismissed() throws {
        var state = CodexNotificationState()
        state.reduce(.permissionRequest(
            sessionID: "permission",
            turnID: "turn-1",
            requestID: permissionRequestID,
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", description: "Run tests"),
            callback: permissionCallback
        ), at: Date(timeIntervalSince1970: 100))

        let pendingNotice = try XCTUnwrap(state.visibleNotification())
        XCTAssertEqual(pendingNotice.permissionCallback, permissionCallback)
        state.dismiss(pendingNotice.id)
        XCTAssertNil(state.visibleNotification())
    }

    func testMalformedOrUnknownHookPayloadThrows() {
        XCTAssertThrowsError(try CodexHookEventParser.parse("not-json"))
        XCTAssertThrowsError(try CodexHookEventParser.parse(#"{"hook_event_name":"Unknown"}"#))
    }

    func testOversizedHookPayloadIsRejectedBeforeParsing() {
        let oversized = Data(
            repeating: 0,
            count: CodexHookEventParser.maximumPayloadBytes + 1
        )

        XCTAssertThrowsError(try CodexHookEventParser.parse(oversized)) { error in
            XCTAssertEqual(error as? CodexHookEventParserError, .payloadTooLarge)
        }
    }

    func testNegatedTestFailureDoesNotOverrideSuccessfulResult() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "success",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "Build succeeded. No tests failed."
        ))

        XCTAssertEqual(state.visibleNotification()?.status, .succeeded)
    }

    func testCorrelationIDsDoNotCollideAcrossSessionAndTurnBoundaries() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "a:b",
            turnID: "c",
            cwd: nil,
            result: "First task completed."
        ))
        state.reduce(.stop(
            sessionID: "a",
            turnID: "b:c",
            cwd: nil,
            result: "Second task completed."
        ))

        XCTAssertEqual(state.notifications.count, 2)
        XCTAssertEqual(Set(state.notifications.map(\.sessionID)), ["a", "a:b"])
    }

}
