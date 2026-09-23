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
}
