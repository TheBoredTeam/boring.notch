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
            #"{"type":"event_msg","payload":{"type":"user_message","message":"What changed?"}}"#,
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
        XCTAssertEqual(record.latestPrompt, "What changed?")
        XCTAssertEqual(record.latestReply, "Done")
    }

    func testCodexHistoryProvidesPromptWhenTranscriptTailDoesNot() throws {
        let record = try XCTUnwrap(AISessionScanner.parseCodex(
            lines: [#"{"type":"session_meta","payload":{"id":"history-thread"}}"#],
            file: URL(fileURLWithPath: "/tmp/session.jsonl"),
            modifiedAt: Date(),
            historyPrompts: ["history-thread": "Latest question"]
        ))
        XCTAssertEqual(record.latestPrompt, "Latest question")
    }

    func testCodexMetadataLongerThanInitialBufferIsNotDropped() throws {
        let metadata = String(repeating: "x", count: 20 * 1024)
        let header = #"{"type":"session_meta","payload":{"id":"long-thread","cwd":"/tmp/project","originator":"Codex Desktop","extra":"\#(metadata)"}}"#
        let filler = String(repeating: #"{"type":"event_msg","payload":{"type":"other"}}"# + "\n", count: 2_000)
        let data = Data((header + "\n" + filler + #"{"type":"event_msg","payload":{"type":"task_started"}}"# + "\n").utf8)
        XCTAssertGreaterThan(header.utf8.count, 16 * 1024)
        XCTAssertGreaterThan(data.count, 64 * 1024)

        let lines = AISessionScanner.readSessionLines(length: UInt64(data.count)) { offset, count in
            let start = Int(offset)
            return data[start..<min(start + count, data.count)]
        }
        let record = try XCTUnwrap(AISessionScanner.parseCodex(
            lines: lines,
            file: URL(fileURLWithPath: "/tmp/session.jsonl"),
            modifiedAt: Date()
        ))
        XCTAssertEqual(record.id, "codex:long-thread")
        XCTAssertEqual(record.projectName, "project")
        XCTAssertEqual(record.status, .working)
        XCTAssertTrue(record.isDesktopSession)
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
        XCTAssertEqual(completed.latestPrompt, "Help")
        XCTAssertEqual(completed.latestReply, "Finished")
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
        XCTAssertEqual(completed.latestPrompt, "Help")
        XCTAssertEqual(completed.latestReply, "Finished")
    }

    func testSnapshotReconciliationRetainsRecentSessionsAndPrunesOldOnes() throws {
        let now = Date()
        let recent = try XCTUnwrap(AISessionScanner.parseCodex(
            lines: [#"{"type":"session_meta","payload":{"id":"recent"}}"#],
            file: URL(fileURLWithPath: "/tmp/recent.jsonl"),
            modifiedAt: now.addingTimeInterval(-120)
        ))
        let stale = try XCTUnwrap(AISessionScanner.parseCodex(
            lines: [#"{"type":"session_meta","payload":{"id":"stale"}}"#],
            file: URL(fileURLWithPath: "/tmp/stale.jsonl"),
            modifiedAt: now.addingTimeInterval(-3_600)
        ))
        let encoded = try JSONEncoder().encode([recent, stale])
        let restored = try JSONDecoder().decode([AISessionRecord].self, from: encoded)
        let result = AISessionMonitor.reconcile(scanned: [], previous: restored, at: now)
        XCTAssertEqual(result.map(\.id), [recent.id])
    }

    func testCompletionReminderOnlyAppearsForRecentWorkingToIdleTransition() throws {
        let now = Date()
        let file = URL(fileURLWithPath: "/tmp/session.jsonl")
        let working = try XCTUnwrap(AISessionScanner.parseCodex(
            lines: [
                #"{"type":"session_meta","payload":{"id":"transition"}}"#,
                #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
            ], file: file, modifiedAt: now.addingTimeInterval(-10)
        ))
        let completed = try XCTUnwrap(AISessionScanner.parseCodex(
            lines: [
                #"{"type":"session_meta","payload":{"id":"transition"}}"#,
                #"{"type":"event_msg","payload":{"type":"task_complete"}}"#,
            ], file: file, modifiedAt: now
        ))
        XCTAssertEqual(
            AISessionMonitor.completedSessions(before: [working.id: working], after: [completed], at: now).count,
            1
        )
        XCTAssertTrue(AISessionMonitor.completedSessions(
            before: [completed.id: completed], after: [completed], at: now
        ).isEmpty)
    }
}
