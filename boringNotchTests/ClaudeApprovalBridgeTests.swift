//
//  ClaudeApprovalBridgeTests.swift
//  boringNotchTests
//

import XCTest
@testable import boringNotch

final class ClaudeApprovalBridgeTests: XCTestCase {
    func testParsesCompleteLocalHookRequest() throws {
        let body = #"{"hook_event_name":"PermissionRequest","tool_name":"Bash"}"#
        let raw = "POST /claude/permission HTTP/1.1\r\n"
            + "Authorization: Bearer test-token\r\n"
            + "Content-Length: \(body.utf8.count)\r\n\r\n" + body
        let request = try XCTUnwrap(ClaudeApprovalBridge.parseRequest(Data(raw.utf8)))
        XCTAssertEqual(request.path, "/claude/permission")
        XCTAssertEqual(request.authorization, "Bearer test-token")
        XCTAssertEqual(String(data: request.body, encoding: .utf8), body)
    }

    func testIncompleteOrOversizedRequestIsNotAccepted() {
        let incomplete = "POST /claude/permission HTTP/1.1\r\nContent-Length: 12\r\n\r\n{}"
        XCTAssertNil(ClaudeApprovalBridge.parseRequest(Data(incomplete.utf8)))

        let oversized = "POST /claude/permission HTTP/1.1\r\nContent-Length: 999999\r\n\r\n{}"
        XCTAssertNil(ClaudeApprovalBridge.parseRequest(Data(oversized.utf8)))
    }

    func testDecisionOnlyAllowsOrDeniesSingleRequest() {
        for (allow, expected) in [(true, "allow"), (false, "deny")] {
            let payload = ClaudeApprovalBridge.permissionDecision(allow: allow)
            let output = payload["hookSpecificOutput"] as? [String: Any]
            let decision = output?["decision"] as? [String: String]
            XCTAssertEqual(output?["hookEventName"] as? String, "PermissionRequest")
            XCTAssertEqual(decision?["behavior"], expected)
            XCTAssertNil(decision?["updatedPermissions"])
        }
    }

    func testParsesMultipleQuestionsAndRejectsMalformedInput() throws {
        let input: [String: Any] = [
            "questions": [
                ["question": "Framework?", "header": "Framework", "options": [
                    ["label": "SwiftUI", "description": "Native"],
                    ["label": "AppKit"],
                ], "multiSelect": false],
                ["question": "Targets?", "header": "Targets", "options": [
                    ["label": "macOS"], ["label": "iOS"],
                ], "multiSelect": true],
            ],
        ]
        let questions = try XCTUnwrap(ClaudeApprovalBridge.parseQuestions(input))
        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(questions[0].options[0].detail, "Native")
        XCTAssertFalse(questions[0].multiSelect)
        XCTAssertTrue(questions[1].multiSelect)
        XCTAssertNil(ClaudeApprovalBridge.parseQuestions(["questions": []]))
        XCTAssertNil(ClaudeApprovalBridge.parseQuestions(["questions": [
            ["question": "Broken", "options": [["description": "Missing label"]]],
        ]]))
        XCTAssertNil(ClaudeApprovalBridge.parseQuestions(["questions": [
            ["question": "Duplicate?", "options": [["label": "Yes"]]],
            ["question": "Duplicate?", "options": [["label": "No"]]],
        ]]))
        XCTAssertNil(ClaudeApprovalBridge.parseQuestions(["questions": [
            ["question": "Choice?", "options": [["label": "Same"], ["label": "Same"]]],
        ]]))
    }

    func testQuestionDecisionPreservesInputAndAddsAnswers() throws {
        let questions: [[String: Any]] = [[
            "question": "Framework?", "header": "Framework",
            "options": [["label": "SwiftUI"], ["label": "AppKit"]],
            "multiSelect": false,
        ]]
        let payload = ClaudeApprovalBridge.questionDecision(
            input: ["questions": questions, "metadata": "keep"],
            answers: ["Framework?": "SwiftUI"]
        )
        let output = try XCTUnwrap(payload["hookSpecificOutput"] as? [String: Any])
        let updated = try XCTUnwrap(output["updatedInput"] as? [String: Any])
        XCTAssertEqual(output["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(output["permissionDecision"] as? String, "allow")
        XCTAssertEqual(updated["metadata"] as? String, "keep")
        XCTAssertEqual((updated["questions"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((updated["answers"] as? [String: String])?["Framework?"], "SwiftUI")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: payload))
    }

    func testHookSetupPreservesUnrelatedSettingsAndUsesOneToken() throws {
        let token = String(repeating: "a", count: 64)
        let original: [String: Any] = [
            "model": "keep-this",
            "hooks": [
                "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "true"]]]],
                "Stop": [["hooks": [["type": "command", "command": "true"]]]],
            ],
        ]
        let updated = try ClaudeApprovalBridge.settingsWithHooks(original, token: token)
        let hooks = try XCTUnwrap(updated["hooks"] as? [String: Any])
        XCTAssertEqual(updated["model"] as? String, "keep-this")
        XCTAssertEqual((hooks["Stop"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((hooks["PreToolUse"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(ClaudeApprovalBridge.token(in: hooks), token)
        XCTAssertTrue(ClaudeApprovalBridge.hasHook(
            hooks, event: "PermissionRequest", url: ClaudeApprovalBridge.hookURL,
            token: token, timeout: 25, matcher: ""
        ))
        XCTAssertTrue(ClaudeApprovalBridge.hasHook(
            hooks, event: "PreToolUse", url: ClaudeApprovalBridge.questionHookURL,
            token: token, timeout: 300, matcher: "AskUserQuestion"
        ))
        let repeated = try ClaudeApprovalBridge.settingsWithHooks(updated, token: token)
        let repeatedHooks = try XCTUnwrap(repeated["hooks"] as? [String: Any])
        XCTAssertEqual((repeatedHooks["PreToolUse"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((repeatedHooks["PermissionRequest"] as? [[String: Any]])?.count, 1)
        XCTAssertThrowsError(try ClaudeApprovalBridge.settingsWithHooks(["hooks": "invalid"], token: token))
    }
}
