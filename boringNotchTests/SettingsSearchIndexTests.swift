//
//  SettingsSearchIndexTests.swift
//  boringNotchTests
//

import XCTest
@testable import boringNotch

final class SettingsSearchIndexTests: XCTestCase {
    private let index = SettingsSearchIndex.current()

    func testEntryIDsAreUnique() {
        let ids = index.entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testEveryTabExceptAboutHasEntries() {
        for tab in index.tabs where tab.tab != .about {
            XCTAssertFalse(tab.entries.isEmpty, "\(tab.tab) has no searchable settings")
        }
    }

    func testEntriesHaveATitleAndBelongToTheirTab() {
        for tab in index.tabs {
            for entry in tab.entries {
                XCTAssertFalse(entry.title.isEmpty, entry.id)
                XCTAssertEqual(entry.tab, tab.tab, entry.id)
            }
        }
    }

    // A hidden setting must lead to a setting that is always shown, or search has nothing to point at.
    func testRevealedByChainsEndAtAnAlwaysShownSetting() {
        for entry in index.entries {
            var current = entry
            var steps = 0
            while let parentID = current.revealedByID {
                guard let parent = index.entry(withID: parentID) else {
                    XCTFail("\(current.id) is revealed by \(parentID), which is not in the index")
                    break
                }
                steps += 1
                guard steps <= index.entries.count else {
                    XCTFail("\(entry.id) has a revealedBy cycle")
                    break
                }
                current = parent
            }
        }
    }
}
