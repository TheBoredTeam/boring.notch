// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import boringNotch

final class ExtensionTabDescriptorTests: XCTestCase {
    func testWireContractAndUnknownFields() throws {
        let snapshot = try JSONDecoder().decode(ExtensionTabSnapshot.self, from: Data(
            #"{"tabs":[{"id":"tasks-1","title":"Tasks","symbol":"checklist","future":true}]}"#.utf8))
        try snapshot.validate()
        XCTAssertEqual(snapshot.tabs, [.init(id: "tasks-1", title: "Tasks", symbol: "checklist")])
        XCTAssertTrue(snapshot.tabs[0].supports(.regular))
        XCTAssertFalse(snapshot.tabs[0].supports(.compact))
        XCTAssertNoThrow(try ExtensionTabSnapshot(tabs: []).validate())
    }

    func testPresentationDeclarationsAreExplicitAndValidated() throws {
        for declaration in ["[\"regular\",\"compact\"]", "[\"compact\"]"] {
            let json = "{\"tabs\":[{\"id\":\"tasks\",\"title\":\"Tasks\",\"symbol\":\"checklist\",\"presentations\":\(declaration)}]}"
            let snapshot = try JSONDecoder().decode(ExtensionTabSnapshot.self, from: Data(json.utf8))
            try snapshot.validate()
            XCTAssertTrue(snapshot.tabs[0].supports(.compact))
        }
        for declaration in ["null", "[]", "[\"regular\",\"regular\"]", "[\"compact\",\"unknown\"]", "\"compact\""] {
            let json = "{\"tabs\":[{\"id\":\"tasks\",\"title\":\"Tasks\",\"symbol\":\"checklist\",\"presentations\":\(declaration)}]}"
            XCTAssertThrowsError(try JSONDecoder().decode(ExtensionTabSnapshot.self, from: Data(json.utf8)).validate(), declaration)
        }
    }

    func testLayoutContextCarriesNativeBoundsAndExplicitNullDisplay() throws {
        let context = ExtensionTabLayoutContext(presentation: .compact, displayID: nil,
                                               contentSize: CGSize(width: 336, height: 132))
        XCTAssertTrue(context.isValid)
        let data = try JSONEncoder().encode(context)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["presentation"] as? String, "compact")
        XCTAssertTrue(json["displayID"] is NSNull)
        let size = try XCTUnwrap(json["contentSize"] as? [String: Double])
        XCTAssertEqual(size, ["width": 336, "height": 132])
        XCTAssertEqual(try JSONDecoder().decode(ExtensionTabLayoutContext.self, from: data), context)
        for size in [CGSize.zero, CGSize(width: -1, height: 132), CGSize(width: 336, height: 0),
                     CGSize(width: CGFloat.infinity, height: 132), CGSize(width: 336, height: CGFloat.nan)] {
            XCTAssertFalse(ExtensionTabLayoutContext(presentation: .compact, displayID: nil, contentSize: size).isValid)
        }
        for displayID in ["", String(repeating: "a", count: 129)] {
            XCTAssertFalse(ExtensionTabLayoutContext(presentation: .regular, displayID: displayID,
                                                    contentSize: CGSize(width: 320, height: 132)).isValid)
        }
        for size in [CGSize(width: 337, height: 132), CGSize(width: 336, height: 133)] {
            XCTAssertFalse(ExtensionTabLayoutContext(presentation: .compact, displayID: nil, contentSize: size).isValid)
            XCTAssertTrue(ExtensionTabLayoutContext(presentation: .regular, displayID: nil, contentSize: size).isValid)
        }
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
