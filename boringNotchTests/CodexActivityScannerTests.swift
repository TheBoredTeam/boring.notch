import Foundation
import SQLite3
import XCTest

@testable import boringNotch

final class CodexActivityScannerTests: XCTestCase {
    func testRuntimeIDsResolveToConversationNamesAndPersistLocally() async throws {
        try await MainActor.run {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let id = try fixture.conversation(number: 1, name: "Build release", status: "inProgress")
            let before = try Data(contentsOf: fixture.state)
            let result = CodexActivityScanner.scan(in: fixture.root, titleIndexURL: fixture.cache)
            XCTAssertNil(result.errorMessage)
            XCTAssertEqual(result.totalCount, 1)
            XCTAssertEqual(result.activities.first?.id, id)
            XCTAssertEqual(result.activities.first?.title, "Build release")
            XCTAssertEqual(try Data(contentsOf: fixture.state), before, "The source index must remain read-only")
            let index = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixture.cache))
            XCTAssertEqual(index[id], "Build release")
            try fixture.execute(fixture.state, "UPDATE threads SET name = '', title = ''")
            let cached = CodexActivityScanner.scan(in: fixture.root, titleIndexURL: fixture.cache)
            XCTAssertEqual(cached.activities.first?.title, "Build release")
        }
    }

    func testMultipleRunningConversationsAndTerminalStates() async throws {
        try await MainActor.run {
            let fixture = try Fixture()
            defer { fixture.remove() }
            _ = try fixture.conversation(number: 1, name: "Build", status: "inProgress")
            _ = try fixture.conversation(number: 2, name: "Review", status: "inProgress")
            _ = try fixture.conversation(number: 3, name: "Deploy", status: "failed")
            _ = try fixture.conversation(number: 4, name: "Research", status: "interrupted")
            let result = CodexActivityScanner.scan(in: fixture.root, titleIndexURL: fixture.cache)
            XCTAssertEqual(result.totalCount, 2)
            XCTAssertEqual(result.activities.count, 4)
            XCTAssertTrue(result.activities.prefix(2).allSatisfy { $0.status == .running })
            XCTAssertEqual(result.activities.first { $0.title == "Deploy" }?.status, .failed)
            XCTAssertEqual(result.activities.first { $0.title == "Research" }?.status, .interrupted)
        }
    }

    func testNewerCompletedTurnSupersedesOlderRunningRecord() async throws {
        try await MainActor.run {
            let fixture = try Fixture()
            defer { fixture.remove() }
            _ = try fixture.conversation(number: 1, name: "Finished", status: "completed")
            try fixture.turn(number: 1, status: "inProgress", age: 120, ordinal: 1)
            let result = CodexActivityScanner.scan(in: fixture.root, titleIndexURL: fixture.cache)
            XCTAssertEqual(result.totalCount, 0)
            XCTAssertEqual(result.activities.first?.status, .completed)
        }
    }

    func testArchivedAndInternalSubagentConversationsAreExcluded() async throws {
        try await MainActor.run {
            let fixture = try Fixture()
            defer { fixture.remove() }
            _ = try fixture.conversation(number: 1, name: "Visible", status: "inProgress")
            _ = try fixture.conversation(number: 2, name: "Archived", status: "inProgress", archived: true)
            _ = try fixture.conversation(number: 3, name: "Internal review", status: "inProgress", subagent: true)
            let result = CodexActivityScanner.scan(in: fixture.root, titleIndexURL: fixture.cache)
            XCTAssertEqual(result.totalCount, 1)
            XCTAssertEqual(result.activities.map(\.title), ["Visible"])
        }
    }

    func testUnreadableHistoryReturnsAnErrorWithoutInventingActivity() async throws {
        try await MainActor.run {
            let fixture = try Fixture()
            defer { fixture.remove() }
            try Data("not a SQLite database".utf8).write(to: fixture.history)
            let result = CodexActivityScanner.scan(in: fixture.root, titleIndexURL: fixture.cache)
            XCTAssertNotNil(result.errorMessage)
            XCTAssertEqual(result.totalCount, 0)
            XCTAssertTrue(result.activities.isEmpty)
        }
    }
}

private final class Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var state: URL { root.appendingPathComponent("state_5.sqlite") }
    var history: URL { root.appendingPathComponent("thread_history_1.sqlite") }
    var cache: URL { root.appendingPathComponent("cache/task-titles.json") }
    let now = Int64(Date().timeIntervalSince1970)

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try execute(state, "CREATE TABLE threads (id TEXT, name TEXT, title TEXT, updated_at INTEGER, archived INTEGER, source TEXT, first_user_message TEXT)")
        try execute(history, "CREATE TABLE thread_turns (thread_id TEXT, status TEXT, started_at INTEGER, completed_at INTEGER, rollout_ordinal INTEGER)")
    }

    func conversation(number: Int, name: String, status: String, archived: Bool = false, subagent: Bool = false) throws -> String {
        let id = identifier(number)
        let source = subagent ? "{\"subagent\":{\"other\":\"guardian\"}}" : "vscode"
        try execute(state, "INSERT INTO threads VALUES ('\(id)', '\(name)', 'Fallback', \(now), \(archived ? 1 : 0), '\(source)', 'PRIVATE BODY MUST NOT BE QUERIED')")
        let directory = root.appendingPathComponent("sessions/2026/10/23")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("rollout-2026-10-23T00-00-00-\(id)_\(identifier(100 + number)).jsonl")
        try Data("Contents are deliberately not JSON; correlation uses filenames only.".utf8).write(to: file)
        try turn(number: number, status: status, age: 30, ordinal: 2)
        return id
    }

    func turn(number: Int, status: String, age: Int64, ordinal: Int) throws {
        let completed = status == "inProgress" ? "NULL" : String(now)
        try execute(history, "INSERT INTO thread_turns VALUES ('\(identifier(100 + number))', '\(status)', \(now - age), \(completed), \(ordinal))")
    }

    func execute(_ file: URL, _ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(file.path, &database) == SQLITE_OK, let database else {
            throw NSError(domain: "CodexScannerFixture", code: 1)
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "CodexScannerFixture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
        }
    }

    private func identifier(_ value: Int) -> String {
        String(format: "00000000-0000-0000-0000-%012d", value)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
