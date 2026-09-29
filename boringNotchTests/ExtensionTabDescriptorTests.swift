// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import boringNotch

final class ExtensionTabDescriptorTests: XCTestCase {
    func testWireContractAndUnknownFields() throws {
        let snapshot = try JSONDecoder().decode(ExtensionTabSnapshot.self, from: Data(
            #"{"tabs":[{"id":"tasks-1","title":"Tasks","symbol":"checklist","future":true}]}"#.utf8))
        try snapshot.validate()
        XCTAssertEqual(snapshot.tabs, [.init(id: "tasks-1", title: "Tasks", symbol: "checklist")])
        XCTAssertNoThrow(try ExtensionTabSnapshot(tabs: []).validate())
    }

    func testIDsAndDuplicateSnapshotsAreRejected() {
        for id in ["", "../home", "provider/home", "tab\n", String(repeating: "a", count: 101)] {
            XCTAssertThrowsError(try ExtensionTabDescriptor(id: id, title: "Tasks", symbol: "checklist").validate())
        }
        let tab = ExtensionTabDescriptor(id: "tasks", title: "Tasks", symbol: "checklist")
        XCTAssertThrowsError(try ExtensionTabSnapshot(tabs: [tab, tab]).validate())
        XCTAssertThrowsError(try ExtensionTabSnapshot(tabs: (0..<9).map {
            .init(id: "tab-\($0)", title: "Tasks", symbol: "checklist")
        }).validate())
    }

    func testChromeMetadataHasUTF8AndControlCharacterBounds() {
        for title in ["", "  ", "line\nbreak", "tab\tname", String(repeating: "a", count: 65), String(repeating: "é", count: 33)] {
            XCTAssertThrowsError(try ExtensionTabDescriptor(id: "tasks", title: title, symbol: "checklist").validate())
        }
        XCTAssertNoThrow(try ExtensionTabDescriptor(id: "tasks", title: String(repeating: "é", count: 32), symbol: "checklist").validate())
        XCTAssertThrowsError(try ExtensionTabDescriptor(id: "tasks", title: "Tasks", symbol: String(repeating: "x", count: 129)).validate())
    }

    @MainActor
    func testUnknownAndEmptySymbolsUseNativeFallback() {
        for symbol in ["", "not.a.real.system.symbol", "../file.png"] {
            XCTAssertEqual(ExtensionTabDescriptor(id: "tasks", title: "Tasks", symbol: symbol).systemSymbol,
                           "puzzlepiece.extension")
        }
        XCTAssertEqual(ExtensionTabDescriptor(id: "tasks", title: "Tasks", symbol: "house.fill").systemSymbol, "house.fill")
    }
}
