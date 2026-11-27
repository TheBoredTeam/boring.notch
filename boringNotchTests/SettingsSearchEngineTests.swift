//
//  SettingsSearchEngineTests.swift
//  boringNotchTests
//

import XCTest
@testable import boringNotch

final class SettingsSearchEngineTests: XCTestCase {
    /// A small hand-written index, so the tests do not depend on the real settings or the app language.
    private let index = SettingsSearchIndex(tabs: [
        .init(tab: .general, title: "General", entries: [
            .init(id: "general.menuBarIcon", tab: .general, title: "Show menu bar icon", section: "App"),
            .init(
                id: "general.launchAtLogin", tab: .general, title: "Launch at login", section: "App",
                keywords: ["Startup"])
        ]),
        .init(tab: .notch, title: "Notch", entries: [
            .init(id: "notch.openOnHover", tab: .notch, title: "Open notch on hover", section: "Behavior"),
            .init(
                id: "notch.hoverDelay", tab: .notch, title: "Hover delay", section: "Behavior",
                revealedByID: "notch.openOnHover"),
            .init(id: "notch.extendHoverArea", tab: .notch, title: "Extend hover area", section: "Window"),
            .init(id: "notch.shadow", tab: .notch, title: "Enable window shadow", section: "Window")
        ]),
        .init(tab: .osd, title: "OSD", entries: [
            .init(
                id: "osd.replace", tab: .osd, title: "Replace System OSD", section: "General",
                keywords: ["HUD", "Volume", "Brightness"]),
            .init(
                id: "osd.closedPercentage", tab: .osd, title: "Show percentage (closed notch)",
                section: "Visibility", revealedByID: "osd.replace"),
            .init(id: "osd.cafe", tab: .osd, title: "Café mode", section: "Visibility")
        ]),
        .init(tab: .about, title: "About", entries: [])
    ])

    private func ids(_ query: String) -> [String] {
        SettingsSearchEngine.search(query, in: index).flatMap(\.entries).map(\.id)
    }

    private func tabs(_ query: String) -> [SettingsTab] {
        SettingsSearchEngine.search(query, in: index).map(\.tab)
    }

    func testEmptyOrBlankQueryFindsNothing() {
        XCTAssertTrue(SettingsSearchEngine.search("", in: index).isEmpty)
        XCTAssertTrue(SettingsSearchEngine.search("   ", in: index).isEmpty)
        XCTAssertTrue(SettingsSearchEngine.search("()", in: index).isEmpty)
    }

    func testUnknownWordFindsNothing() {
        XCTAssertTrue(SettingsSearchEngine.search("zzzz", in: index).isEmpty)
    }

    func testTitleStartingWithQueryRanksFirst() {
        XCTAssertEqual(ids("hover"), ["notch.hoverDelay", "notch.openOnHover", "notch.extendHoverArea"])
    }

    func testEqualRanksKeepOnScreenOrder() {
        XCTAssertEqual(ids("window"), ["notch.shadow", "notch.extendHoverArea"])
        XCTAssertEqual(ids("show"), ["general.menuBarIcon", "osd.closedPercentage"])
    }

    func testWordPrefixBeatsMatchInsideAWord() {
        // "on" is a whole word in one title and only the end of "icon" in the other.
        XCTAssertEqual(ids("on"), ["notch.openOnHover", "general.menuBarIcon"])
    }

    func testEveryWordOfTheQueryMustMatch() {
        XCTAssertEqual(ids("hover delay"), ["notch.hoverDelay"])
        XCTAssertTrue(ids("hover zzzz").isEmpty)
    }

    func testWordsCanMatchDifferentFields() {
        XCTAssertEqual(ids("osd percent"), ["osd.closedPercentage"])
        XCTAssertEqual(ids("behavior delay"), ["notch.hoverDelay"])
    }

    func testMatchingIgnoresCaseAndAccents() {
        XCTAssertEqual(ids("HOVER DELAY"), ["notch.hoverDelay"])
        XCTAssertEqual(ids("cafe"), ["osd.cafe"])
        XCTAssertEqual(ids("CAFÉ"), ["osd.cafe"])
    }

    func testKeywordsFindSettings() {
        XCTAssertEqual(ids("hud"), ["osd.replace"])
        XCTAssertEqual(ids("startup"), ["general.launchAtLogin"])
    }

    func testSectionNameFindsItsSettings() {
        XCTAssertEqual(ids("app"), ["general.menuBarIcon", "general.launchAtLogin"])
    }

    func testTabNameFindsAllOfItsSettings() {
        // The one title that contains the word comes first, the rest keep their on-screen order.
        XCTAssertEqual(
            SettingsSearchEngine.search("notch", in: index).first?.entries.map(\.id),
            ["notch.openOnHover", "notch.hoverDelay", "notch.extendHoverArea", "notch.shadow"])
    }

    func testTabWithoutEntriesIsFoundByName() {
        let groups = SettingsSearchEngine.search("about", in: index)
        XCTAssertEqual(groups.map(\.tab), [.about])
        XCTAssertEqual(groups.first?.entries, [])
    }

    func testTabWithBestMatchComesFirst() {
        // "General" is a section in OSD and the name of the General tab. A section match is the closer one.
        XCTAssertEqual(tabs("general"), [.osd, .general])
        // Equal best matches keep sidebar order.
        XCTAssertEqual(tabs("notch"), [.notch, .osd])
    }

    func testPunctuationInQueryIsIgnored() {
        XCTAssertEqual(ids("(closed notch)"), ["osd.closedPercentage"])
    }
}
