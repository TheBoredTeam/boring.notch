import XCTest

@MainActor
final class BoringNotchUITests: XCTestCase, @unchecked Sendable {
    private var app: XCUIApplication!

    nonisolated override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = ["--uitesting"]
            app.launch()
        }
    }

    nonisolated override func tearDown() async throws {
        await MainActor.run {
            if testRun?.hasSucceeded == false {
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "UI failure"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            app.typeKey("q", modifierFlags: .command)
            _ = app.wait(for: .notRunning, timeout: 5)
        }
        try await super.tearDown()
    }

    func testGlancesDashboardShowsEveryConfiguredCard() {
        let dashboard = app.scrollViews["productivity-dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))

        let cardIdentifiers = [
            "widget-downloads",
            "widget-bluetooth",
            "widget-weather",
            "widget-clipboard",
            "widget-focus-timer",
            "widget-next-meeting",
        ]
        for identifier in cardIdentifiers {
            let card = app.descendants(matching: .any)[identifier]
            var attempts = 0
            while !card.exists && attempts < 6 {
                dashboard.swipeLeft()
                attempts += 1
            }
            XCTAssertTrue(card.exists, "Missing card: \(identifier)")
        }
    }

    func testPrimaryTabsNavigateWithoutClosingTheNotch() {
        let shelfTab = app.buttons["tab-shelf"]
        XCTAssertTrue(shelfTab.waitForExistence(timeout: 5))
        shelfTab.click()
        XCTAssertTrue(app.descendants(matching: .any)["shelf-view"].waitForExistence(timeout: 2))

        app.buttons["tab-home"].click()
        XCTAssertTrue(app.descendants(matching: .any)["home-view"].waitForExistence(timeout: 2))

        app.buttons["tab-glances"].click()
        XCTAssertTrue(app.scrollViews["productivity-dashboard"].waitForExistence(timeout: 2))
    }

    func testGlancesSettingsAreReachable() {
        let settingsButton = app.buttons["notch-settings-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        let glancesNavigation = app.buttons["settings-glances-navigation"]
        XCTAssertTrue(glancesNavigation.waitForExistence(timeout: 5))
        glancesNavigation.click()
        XCTAssertTrue(app.staticTexts["Glances layout"].waitForExistence(timeout: 3))
    }
}
