import XCTest
@testable import DailyPlanningCore

final class DailyConclusionStoreTests: XCTestCase {
    func testMarkdownIsSavedVerbatimAndExistingEntryIsPreserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let markdown = "# A day\n\n- [x] Done\n\n```swift\nlet x = 1\n```\n**Grateful**  \nNext line 🌓"
        let date = Date(timeIntervalSince1970: 1_790_208_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = DailyConclusionStore()
        let first = try XCTUnwrap(store.save(text: markdown, date: date, directory: folder, calendar: calendar))
        let second = try XCTUnwrap(store.save(text: "Another entry", date: date, directory: folder, calendar: calendar))
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), markdown)
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "Another entry")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.deletingPathExtension().lastPathComponent, first.deletingPathExtension().lastPathComponent + "-2")
        XCTAssertEqual(first.pathExtension, "md")
    }

    func testBlankEntryDoesNotCreateFilesOrRequireAnExistingFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for text in ["", " \n\t\r\n", "\u{2003}"] {
            XCTAssertNil(try DailyConclusionStore().save(text: text, date: Date(), directory: folder))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testMissingFolderFailsWithoutDiscardingInputOrRecreatingFolder() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try DailyConclusionStore().save(text: "Keep this", date: Date(), directory: folder))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testConclusionPreferencesPersistSeparatelyFromSchedule() throws {
        let suite = "DiaryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DailyWorkflowPreferencesStore(defaults: defaults)
        var schedule = DailyWorkflowPreferences.default
        schedule.eveningReviewEnabled = true
        try store.savePreferences(schedule)
        var conclusion = DailyConclusionPreferences()
        XCTAssertFalse(conclusion.isEnabled)
        XCTAssertTrue(conclusion.directoryPath.hasSuffix("/Documents/Boring Notch Diary"))
        conclusion.isEnabled = true
        conclusion.directoryPath = "/tmp/Diary"
        conclusion.directoryBookmark = Data([1, 2, 3])
        try store.saveConclusionPreferences(conclusion)
        let reloaded = DailyWorkflowPreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.loadPreferences(), schedule)
        XCTAssertEqual(reloaded.loadConclusionPreferences(), conclusion)
    }
}
