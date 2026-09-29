// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import boringNotch

final class NotchWorkspaceLayoutTests: XCTestCase {
    private let extensionTab = NotchViews.extensionTab(.init(providerID: "org.example.focus", localID: "focus"))

    func testCompactHomeKeepsNaturalHeightAndNarrowPlayer() {
        let layout = layout(compact: true, selection: .home)

        XCTAssertTrue(layout.usesCompactHome)
        XCTAssertEqual(layout.contentWidth, 336)
        XCTAssertNil(layout.contentHeight)
        XCTAssertNil(layout.notchHeight)
    }

    func testCompactShelfAndExtensionGetTheSameFiniteWorkspace() {
        for selection in [NotchViews.shelf, extensionTab] {
            let layout = layout(compact: true, selection: selection)

            XCTAssertFalse(layout.usesCompactHome)
            XCTAssertEqual(layout.notchHeight, 190)
            XCTAssertEqual(layout.contentWidth, 546)
            XCTAssertEqual(layout.contentHeight, 132)
        }
    }

    func testRegularModeKeepsExistingContentBoundsForEveryTab() {
        for selection in [NotchViews.home, .shelf, extensionTab] {
            let layout = layout(compact: false, selection: selection)

            XCTAssertFalse(layout.usesCompactHome)
            XCTAssertEqual(layout.notchHeight, 190)
            XCTAssertEqual(layout.contentWidth, 578)
            XCTAssertEqual(layout.contentHeight, 132)
        }
    }

    func testCompactExternalDisplayUsesSpaceBelowItsOwnClearance() {
        let layout = NotchWorkspaceLayout(compactMode: true, selection: extensionTab,
            standardSize: CGSize(width: 640, height: 190), horizontalInset: 47, topClearance: 11)

        XCTAssertEqual(layout.contentHeight, 159)
        XCTAssertEqual(layout.notchHeight, 190)
    }

    func testShrinkingWorkspaceNeverOffersNegativeNativeBounds() {
        let layout = NotchWorkspaceLayout(compactMode: true, selection: extensionTab,
            standardSize: CGSize(width: 70, height: 38), horizontalInset: 47, topClearance: 38)

        XCTAssertEqual(layout.contentWidth, 0)
        XCTAssertEqual(layout.contentHeight, 0)
    }

    func testFloatingTabsSizeToContentsAndCapLargeCollections() {
        XCTAssertEqual(NotchTabStripMetrics.floatingContentWidth(tabCount: 3, maximumWidth: 336), 132)
        XCTAssertEqual(NotchTabStripMetrics.floatingContentWidth(tabCount: 100, maximumWidth: 336), 320)
        XCTAssertEqual(NotchTabStripMetrics.floatingContentWidth(tabCount: 3, maximumWidth: 10), 0)
        XCTAssertEqual(NotchTabStripMetrics.floatingContentWidth(tabCount: 0, maximumWidth: 336), 0)
    }

    private func layout(compact: Bool, selection: NotchViews) -> NotchWorkspaceLayout {
        NotchWorkspaceLayout(compactMode: compact, selection: selection,
            standardSize: CGSize(width: 640, height: 190), horizontalInset: compact ? 47 : 31,
            topClearance: 38)
    }
}
