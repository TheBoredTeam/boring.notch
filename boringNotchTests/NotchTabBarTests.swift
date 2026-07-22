import XCTest
@testable import boringNotch

final class NotchTabBarTests: XCTestCase {
    func testTabsIncludeOnlyHomeWhenShelfHidden() {
        let tabs = NotchTabBar.tabs(showShelf: false)
        XCTAssertEqual(tabs.map(\.view), [.home])
        XCTAssertEqual(tabs.map(\.icon), ["house.fill"])
    }

    func testTabsIncludeHomeAndShelfWhenShelfEnabled() {
        let tabs = NotchTabBar.tabs(showShelf: true)
        XCTAssertEqual(tabs.map(\.view), [.home, .shelf])
        XCTAssertEqual(tabs.map(\.icon), ["house.fill", "tray.fill"])
    }

    func testShouldShowTabBarRequiresShelfFeatureAndEitherItemsOrAlwaysShow() {
        XCTAssertFalse(NotchTabBar.shouldShowTabBar(boringShelf: false, shelfHasItems: true, alwaysShowTabs: true))
        XCTAssertFalse(NotchTabBar.shouldShowTabBar(boringShelf: true, shelfHasItems: false, alwaysShowTabs: false))
        XCTAssertTrue(NotchTabBar.shouldShowTabBar(boringShelf: true, shelfHasItems: true, alwaysShowTabs: false))
        XCTAssertTrue(NotchTabBar.shouldShowTabBar(boringShelf: true, shelfHasItems: false, alwaysShowTabs: true))
    }
}
