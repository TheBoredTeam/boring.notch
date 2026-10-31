// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import XCTest
@testable import boringNotch

final class NotchWorkspaceLayoutTests: XCTestCase {
    func testEveryCompactTabSharesAStrictlySmallerFiniteRegion() {
        let layout = layout(compact: true)

        XCTAssertEqual(layout.contentWidth, 336)
        XCTAssertEqual(layout.contentHeight, 132)
        XCTAssertEqual(layout.notchHeight, 190)
        XCTAssertLessThan(layout.contentWidth + 2 * layout.horizontalInset, layout.standardSize.width)
    }

    func testRegularModeKeepsExistingContentBoundsForEveryTab() {
        let layout = layout(compact: false)

        XCTAssertEqual(layout.notchHeight, 190)
        XCTAssertEqual(layout.contentWidth, 578)
        XCTAssertEqual(layout.contentHeight, 132)
    }

    func testCompactExternalDisplayUsesSpaceBelowItsOwnClearance() {
        let layout = NotchWorkspaceLayout(compactMode: true,
            standardSize: CGSize(width: 640, height: 190), horizontalInset: 47, topClearance: 11)

        XCTAssertEqual(layout.contentHeight, 132)
        XCTAssertEqual(layout.notchHeight, 163)
    }

    func testExtraNotchClearanceCanOnlyReduceCompactContent() {
        let layout = NotchWorkspaceLayout(compactMode: true,
            standardSize: CGSize(width: 640, height: 190), horizontalInset: 47, topClearance: 80)

        XCTAssertEqual(layout.contentHeight, 90)
        XCTAssertEqual(layout.notchHeight, 190)
    }

    func testShrinkingWorkspaceNeverOffersNegativeNativeBounds() {
        let layout = NotchWorkspaceLayout(compactMode: true,
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

    func testBothStandardPlacementsRespectShelfAndAlwaysShowTabsPreferences() {
        XCTAssertFalse(NotchTabVisibility.shouldShow(compactMode: false, shelfEnabled: true,
            shelfIsEmpty: true, alwaysShowTabs: false, hasExtensionTabs: false))
        XCTAssertTrue(NotchTabVisibility.shouldShow(compactMode: false, shelfEnabled: true,
            shelfIsEmpty: true, alwaysShowTabs: true, hasExtensionTabs: false))
        XCTAssertTrue(NotchTabVisibility.shouldShow(compactMode: false, shelfEnabled: true,
            shelfIsEmpty: false, alwaysShowTabs: false, hasExtensionTabs: false))
        XCTAssertFalse(NotchTabVisibility.shouldShow(compactMode: false, shelfEnabled: false,
            shelfIsEmpty: false, alwaysShowTabs: true, hasExtensionTabs: false))
    }

    func testCompactKeepsEnabledShelfAvailableWithoutAlwaysShowTabs() {
        XCTAssertTrue(NotchTabVisibility.shouldShow(compactMode: true, shelfEnabled: true,
            shelfIsEmpty: true, alwaysShowTabs: false, hasExtensionTabs: false))
        XCTAssertFalse(NotchTabVisibility.shouldShow(compactMode: true, shelfEnabled: false,
            shelfIsEmpty: true, alwaysShowTabs: true, hasExtensionTabs: false))
    }

    func testEligibleExtensionsKeepTabsVisibleInEitherMode() {
        for compactMode in [false, true] {
            XCTAssertTrue(NotchTabVisibility.shouldShow(compactMode: compactMode, shelfEnabled: false,
                shelfIsEmpty: true, alwaysShowTabs: false, hasExtensionTabs: true))
        }
    }

    private func layout(compact: Bool) -> NotchWorkspaceLayout {
        NotchWorkspaceLayout(compactMode: compact,
            standardSize: CGSize(width: 640, height: 190), horizontalInset: compact ? 47 : 31,
            topClearance: 38)
    }
}
