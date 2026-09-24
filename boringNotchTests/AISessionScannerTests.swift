//
//  AISessionScannerTests.swift
//  boringNotchTests
//

import XCTest
@testable import boringNotch

final class AISessionScannerTests: XCTestCase {
    func testCodexOpenTaskIsWorking() throws {
        let lines = [
            #"{"type":"session_meta","payload":{"id":"thread-1","cwd":"/tmp/example","originator":"Codex Desktop"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
        ]
        let record = try XCTUnwrap(AISessionScanner.parseCodex(
            lines: lines,
            file: URL(fileURLWithPath: "/tmp/session.jsonl"),
            modifiedAt: Date()
        ))
        XCTAssertEqual(record.id, "codex:thread-1")
        XCTAssertEqual(record.projectName, "example")
        XCTAssertEqual(record.status, .working)
        XCTAssertTrue(record.isDesktopSession)
    }

    func testCodexCompletedTaskIsIdle() throws {
        let lines = [
            #"{"type":"session_meta","payload":{"id":"thread-2"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Done"}}"#,
        ]
        let record = try XCTUnwrap(AISessionScanner.parseCodex(
            lines: lines,
            file: URL(fileURLWithPath: "/tmp/session.jsonl"),
            modifiedAt: Date()
        ))
        XCTAssertEqual(record.status, .idle)
        XCTAssertEqual(record.latestMessage, "Done")
    }

    func testClaudeToolUseIsWorkingAndAssistantReplyIsIdle() throws {
        let lines = [
            #"{"type":"user","sessionId":"session-1","cwd":"/tmp/project","message":{"content":"Help"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read"}]}}"#,
        ]
        let file = URL(fileURLWithPath: "/tmp/session-1.jsonl")
        let working = try XCTUnwrap(AISessionScanner.parseClaude(lines: lines, file: file, modifiedAt: Date()))
        XCTAssertEqual(working.projectName, "project")
        XCTAssertEqual(working.status, .working)

        let completed = try XCTUnwrap(AISessionScanner.parseClaude(
            lines: lines + [#"{"type":"assistant","message":{"content":[{"type":"text","text":"Finished"}]}}"#],
            file: file,
            modifiedAt: Date()
        ))
        XCTAssertEqual(completed.status, .idle)
        XCTAssertEqual(completed.latestMessage, "Finished")
    }

    func testOpenClawToolCallIsWorkingAndAssistantReplyIsIdle() throws {
        let lines = [
            #"{"type":"session","id":"session-3","cwd":"/tmp/workspace"}"#,
            #"{"type":"message","message":{"role":"user","content":[{"type":"text","text":"Help"}]}}"#,
            #"{"type":"message","message":{"role":"assistant","content":[{"type":"thinking","thinking":"private"},{"type":"toolCall","name":"read"}]}}"#,
        ]
        let file = URL(fileURLWithPath: "/tmp/agents/main/sessions/session-3.jsonl")
        let working = try XCTUnwrap(AISessionScanner.parseOpenClaw(lines: lines, file: file, modifiedAt: Date()))
        XCTAssertEqual(working.id, "openclaw:session-3")
        XCTAssertEqual(working.projectName, "workspace")
        XCTAssertEqual(working.status, .working)
        XCTAssertNil(working.latestMessage)

        let completed = try XCTUnwrap(AISessionScanner.parseOpenClaw(
            lines: lines + [#"{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"Finished"}]}}"#],
            file: file,
            modifiedAt: Date()
        ))
        XCTAssertEqual(completed.status, .idle)
        XCTAssertEqual(completed.latestMessage, "Finished")
    }
}
