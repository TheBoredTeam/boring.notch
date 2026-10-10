// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import XCTest
import AppKit
import ImageIO
@testable import boringNotch

final class ExtensionTabDescriptorTests: XCTestCase {
    @MainActor
    func testOptionalPublisherIconDecodesAsBoundedTemplate() throws {
        let png = try TabIconFixture.png(width: 128, height: 64)
        let json = try JSONSerialization.data(withJSONObject: ["tabs": [["id": "tasks", "title": "Tasks", "symbol": "checklist", "iconPNG": png]]])
        let snapshot = try JSONDecoder().decode(ExtensionTabSnapshot.self, from: json)
        try snapshot.validate()
        XCTAssertEqual(snapshot.tabs.first?.iconPNG, png)
        let icon = try XCTUnwrap(ExtensionTabIcon.decode(png))
        XCTAssertTrue(icon.isTemplate)
        XCTAssertEqual(icon.size, NSSize(width: 16, height: 8))
    }

    @MainActor
    func testInvalidOptionalIconPreservesTabAndSymbolFallback() throws {
        let values: [Any] = [NSNull(), 42, [:], "", "not base64", "data:image/png;base64,AA==",
                             String(repeating: "A", count: ExtensionTabIcon.maximumEncodedBytes + 1)]
        for value in values {
            let json = try JSONSerialization.data(withJSONObject: ["tabs": [["id": "tasks", "title": "Tasks", "symbol": "house.fill", "iconPNG": value]]])
            let snapshot = try JSONDecoder().decode(ExtensionTabSnapshot.self, from: json)
            try snapshot.validate()
            XCTAssertEqual(snapshot.tabs.count, 1)
            XCTAssertEqual(snapshot.tabs[0].systemSymbol, "house.fill")
            XCTAssertNil(ExtensionTabIcon.decode(snapshot.tabs[0].iconPNG))
        }
        let atLimit = String(repeating: "A", count: ExtensionTabIcon.maximumEncodedBytes)
        XCTAssertEqual(ExtensionTabDescriptor(id: "tasks", title: "Tasks", symbol: "square", iconPNG: atLimit).iconPNG, atLimit)
        XCTAssertNil(ExtensionTabDescriptor(id: "tasks", title: "Tasks", symbol: "square", iconPNG: atLimit + "A").iconPNG)
    }

    @MainActor
    func testIconRejectsLargeAnimatedTruncatedNonPNGAndConcatenatedImages() throws {
        XCTAssertNil(ExtensionTabIcon.decode(try TabIconFixture.png(width: 129, height: 1)))
        XCTAssertNil(ExtensionTabIcon.decode(try TabIconFixture.png(width: 1, height: 129)))
        XCTAssertNil(ExtensionTabIcon.decode(try TabIconFixture.png(width: 8, height: 8, type: "public.jpeg")))
        let bytes = try XCTUnwrap(Data(base64Encoded: TabIconFixture.png(width: 72, height: 72)))
        XCTAssertNil(ExtensionTabIcon.decode(bytes.prefix(24).base64EncodedString()))
        XCTAssertNil(ExtensionTabIcon.decode((bytes + bytes).base64EncodedString()))
        var animated = bytes
        animated.insert(contentsOf: [0, 0, 0, 8, 97, 99, 84, 76, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0], at: 33)
        XCTAssertNil(ExtensionTabIcon.decode(animated.base64EncodedString()), "Even one-frame APNG is outside static chrome")
        var oversizedHeader = bytes
        oversizedHeader.replaceSubrange(16..<20, with: [0x7f, 0xff, 0xff, 0xff])
        XCTAssertNil(ExtensionTabIcon.decode(oversizedHeader.base64EncodedString()), "Inspect dimensions before allocating image pixels")
    }

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

enum TabIconFixture {
    static func png(width: Int = 72, height: Int = 72, alpha: CGFloat = 1, type: String = "public.png") throws -> String {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let bitmap = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, bitmap, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return (data as Data).base64EncodedString()
    }
}
