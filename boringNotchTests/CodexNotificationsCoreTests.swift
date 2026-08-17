import XCTest
@testable import CodexNotificationsCore

final class CodexNotificationsCoreTests: XCTestCase {
    private struct Candidate: Equatable {
        let id: String
        let visible: Bool
        let priority: Int
        let updatedAt: Date
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
        state.reduce(try CodexHookEventParser.parse(#"""
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
                "control": "accessibility"
            }
        }
        """#))

        XCTAssertNil(state.visibleNotification())
        let pendingNotice = try XCTUnwrap(state.nativePermissionNotification())
        state.confirmNativePermission(pendingNotice.id)
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
        XCTAssertEqual(
            notice.permissionDetails?.accessibilityMatchCandidates,
            [
                "May I build the Debug app for visual verification?",
                "xcodebuild -scheme boringNotch build"
            ]
        )
    }

    func testPermissionMatchCandidatesKeepDescriptionAndDistinctRawCommand() {
        let details = CodexPermissionDetails(
            toolName: "Bash",
            description: "Allow case3 to create, verify, and delete the test file?",
            command: "touch /tmp/case3 && cat /tmp/case3 && rm /tmp/case3",
            rawCommand: "/bin/zsh -lc 'touch /tmp/case3 && cat /tmp/case3 && rm /tmp/case3'"
        )

        XCTAssertEqual(
            details.accessibilityMatchCandidates,
            [
                "Allow case3 to create, verify, and delete the test file?",
                "/bin/zsh -lc 'touch /tmp/case3 && cat /tmp/case3 && rm /tmp/case3'",
                "touch /tmp/case3 && cat /tmp/case3 && rm /tmp/case3"
            ]
        )
    }

    func testProjectlessPermissionUsesChatMetadataAndPlaceholder() throws {
        var state = CodexNotificationState()
        state.reduce(try CodexHookEventParser.parse(#"""
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
            "boring_notch_approval":{"control":"accessibility"}
        }
        """#))

        XCTAssertNil(state.visibleNotification())
        let pendingNotice = try XCTUnwrap(state.nativePermissionNotification())
        state.confirmNativePermission(pendingNotice.id)
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
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", description: "Build Debug"),
            control: .accessibility
        ))

        XCTAssertNil(state.visibleNotification())
        let pendingNotice = try XCTUnwrap(state.nativePermissionNotification())
        state.confirmNativePermission(pendingNotice.id)
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

    func testParsesNonExpiringAccessibilityPermissionControl() throws {
        var state = CodexNotificationState()
        state.reduce(try CodexHookEventParser.parse(#"""
        {
            "hook_event_name":"PermissionRequest",
            "session_id":"session-1",
            "turn_id":"turn-1",
            "tool_name":"Bash",
            "tool_input":{"command":"xcodebuild -scheme boringNotch build"},
            "boring_notch_approval": {
                "control": "accessibility"
            }
        }
        """#))

        XCTAssertNil(state.visibleNotification())
        let notice = try XCTUnwrap(state.nativePermissionNotification())
        XCTAssertEqual(notice.permissionControl, .accessibility)
    }

    func testPostToolUseDismissesTheMatchingPermissionRequest() throws {
        var state = CodexNotificationState()
        state.reduce(.permissionRequest(
            sessionID: "session-1",
            turnID: "turn-1",
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", description: "Run tests"),
            control: .accessibility
        ))
        XCTAssertNil(state.visibleNotification())
        XCTAssertNotNil(state.nativePermissionNotification())

        state.reduce(try CodexHookEventParser.parse(#"""
        {
            "hook_event_name":"PostToolUse",
            "session_id":"session-1",
            "turn_id":"turn-1",
            "cwd":"/tmp/project"
        }
        """#))

        XCTAssertNil(state.visibleNotification())
        XCTAssertNil(state.nativePermissionNotification())
    }

    func testPermissionRequestWithoutUsableControlIsNotPresented() throws {
        let payloads = [
            #"{"hook_event_name":"PermissionRequest","session_id":"absent"}"#,
            #"{"hook_event_name":"PermissionRequest","session_id":"missing-control","boring_notch_approval":{}}"#,
            #"{"hook_event_name":"PermissionRequest","session_id":"invalid-control","boring_notch_approval":{"control":"hook-output"}}"#
        ]

        for payload in payloads {
            var state = CodexNotificationState()
            state.reduce(try CodexHookEventParser.parse(payload))
            let notice = try XCTUnwrap(state.notifications.first, payload)
            XCTAssertEqual(notice.status, .needsAction(.permission), payload)
            XCTAssertNil(notice.permissionControl, payload)
            XCTAssertNil(state.visibleNotification(), payload)
            XCTAssertNil(state.nativePermissionNotification(), payload)
        }
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
            cwd: "/tmp/project",
            details: CodexPermissionDetails(
                toolName: "Bash",
                description: "Run xcodebuild"
            ),
            control: .accessibility
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
        XCTAssertTrue(CodexJobStatus.needsAction(.systemPermission).isPersistent)
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

    func testSystemSettingsPermissionBlockerStaysActionable() {
        var state = CodexNotificationState()
        state.reduce(.stop(
            sessionID: "system-permission",
            turnID: "turn-1",
            cwd: "/tmp/project",
            result: "The task failed because Local Network access is required. Please enable it in System Settings before I can continue."
        ), at: Date(timeIntervalSince1970: 10))
        state.reduce(.stop(
            sessionID: "documentation",
            turnID: "turn-2",
            cwd: "/tmp/project",
            result: "Updated the documentation for Local Network access in System Settings."
        ), at: Date(timeIntervalSince1970: 11))

        let reminder = state.notifications.first {
            $0.sessionID == "system-permission"
        }
        XCTAssertEqual(reminder?.status, .needsAction(.systemPermission))
        XCTAssertEqual(reminder?.status.title, "System Permission Required")
        XCTAssertTrue(reminder?.status.isPersistent == true)
        XCTAssertEqual(
            state.notifications.first { $0.sessionID == "documentation" }?.status,
            .succeeded
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
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", description: "Run tests"),
            control: .accessibility
        ), at: Date(timeIntervalSince1970: 10))
        let pendingPermission = try XCTUnwrap(state.nativePermissionNotification())
        state.confirmNativePermission(pendingPermission.id)
        state.reduce(.stop(
            sessionID: "complete",
            turnID: "turn-2",
            cwd: "/tmp/other",
            result: "Finished preparing the report."
        ), at: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(state.visibleNotification()?.sessionID, "permission")
    }

    func testPermissionControlPersistsUntilDismissed() throws {
        var state = CodexNotificationState()
        state.reduce(.permissionRequest(
            sessionID: "permission",
            turnID: "turn-1",
            cwd: "/tmp/project",
            details: CodexPermissionDetails(toolName: "Bash", description: "Run tests"),
            control: .accessibility
        ), at: Date(timeIntervalSince1970: 100))

        XCTAssertNil(state.visibleNotification())
        let pendingNotice = try XCTUnwrap(state.nativePermissionNotification())
        state.confirmNativePermission(pendingNotice.id)
        XCTAssertEqual(state.visibleNotification()?.permissionControl, .accessibility)
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

    func testNativePermissionObservationHasBoundedAppearanceWindow() {
        XCTAssertEqual(
            CodexNotificationTiming.nativePermissionAppearanceTimeout,
            10,
            accuracy: 0.001
        )
    }
}
