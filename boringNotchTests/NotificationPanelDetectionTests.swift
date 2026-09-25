//
//  NotificationPanelDetectionTests.swift
//  boringNotchTests
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import XCTest
@testable import boringNotch

final class NotificationPanelDetectionTests: XCTestCase {
    private func element(
        _ id: String,
        subrole: String? = nil,
        identifier: String? = nil,
        children: [NotificationPanelDetection.Attributes] = []
    ) -> NotificationPanelDetection.Attributes {
        .init(
            subrole: { key in key == "AXSubrole" ? subrole : nil },
            identifier: { key in key == "AXIdentifier" ? identifier : nil },
            children: { children }
        )
    }

    private func panelWindow(
        subrole: String? = "AXNotificationCenterPanel",
        withList: Bool = true,
        withButtons: Bool = true
    ) -> NotificationPanelDetection.Attributes {
        let stackedButton: NotificationPanelDetection.Attributes = .init(
            subrole: { key in key == "AXSubrole" ? "AXButton" : nil },
            identifier: { key in key == "AXStackingIdentifier" ? "stack-01234567-89ab-cdef-0123-456789abcdefcom.apple.Safari" : nil },
            children: { [] }
        )
        let listChildren: [NotificationPanelDetection.Attributes] = withButtons ? [stackedButton] : []
        let list = element("list", identifier: withList ? "AXNotificationListItems" : nil, children: listChildren)
        let group = element("group", children: [list])
        return element("window", subrole: subrole, children: [group])
    }

    private func bannerWindow(tokens: [String]) -> NotificationPanelDetection.Attributes {
        let banners = tokens.map { token in
            element("banner-\(token)", subrole: "AXNotificationCenterBanner", identifier: token)
        }
        return element("banner-window", subrole: "AXSystemDialog", children: banners)
    }

    func testPanelWindowWithDocumentedSubroleIsDetected() {
        XCTAssertTrue(NotificationPanelDetection.isPanelWindow(panelWindow()))
    }

    func testPanelWindowWithoutSubroleIsDetectedViaListIdentifier() {
        XCTAssertTrue(NotificationPanelDetection.isPanelWindow(panelWindow(subrole: "AXSystemDialog")))
    }

    func testPanelWindowWithoutListIsDetectedViaStackButtons() {
        XCTAssertTrue(NotificationPanelDetection.isPanelWindow(panelWindow(subrole: nil, withList: false)))
    }

    func testPanelWindowWithNeitherSubroleNorListButStackButtonsIsDetected() {
        XCTAssertTrue(NotificationPanelDetection.isPanelWindow(panelWindow(subrole: nil, withList: false, withButtons: true)))
    }

    func testButtonWithWrongStackingPrefixIsNotDetected() {
        let button: NotificationPanelDetection.Attributes = .init(
            subrole: { key in key == "AXSubrole" ? "AXButton" : nil },
            identifier: { key in key == "AXStackingIdentifier" ? "other-prefix-abc" : nil },
            children: { [] }
        )
        let window = element("window", subrole: "AXSystemDialog", children: [button])
        XCTAssertFalse(NotificationPanelDetection.isPanelWindow(window))
    }

    func testLiveBannerWindowIsNotThePanel() {
        XCTAssertFalse(NotificationPanelDetection.isPanelWindow(bannerWindow(tokens: ["t1", "t2"])))
    }

    func testEmptyDialogWindowIsNotThePanel() {
        XCTAssertFalse(NotificationPanelDetection.isPanelWindow(element("window", subrole: "AXSystemDialog")))
    }

    func testGenericButtonWithoutStackIdentifierIsNotThePanel() {
        let button = element("button", subrole: "AXButton", identifier: nil)
        let window = element("window", subrole: "AXSystemDialog", children: [button])
        XCTAssertFalse(NotificationPanelDetection.isPanelWindow(window))
    }

    func testNilSubroleWindowWithNoChildrenIsNotThePanel() {
        XCTAssertFalse(NotificationPanelDetection.isPanelWindow(element("window")))
    }

    func testDeepHierarchyTerminates() {
        var current = element("leaf")
        for _ in 0..<40 {
            current = element("node", children: [current])
        }
        XCTAssertFalse(NotificationPanelDetection.isPanelWindow(current))
    }

    func testPanelSignalNestedBeyondDepthIsNotReached() {
        var current = panelWindow(subrole: nil)
        for _ in 0..<40 {
            current = element("node", children: [current])
        }
        XCTAssertFalse(NotificationPanelDetection.isPanelWindow(current))
    }

    func testPanelDetectionUsesRealAccessibilityAttributeNames() {
        let axNamedWindow: NotificationPanelDetection.Attributes = .init(
            subrole: { key in key == "AXSubrole" ? "AXNotificationCenterPanel" : nil },
            identifier: { _ in nil },
            children: { [] }
        )
        XCTAssertTrue(NotificationPanelDetection.isPanelWindow(axNamedWindow))

        let legacyNamedWindow: NotificationPanelDetection.Attributes = .init(
            subrole: { key in key == "subrole" ? "AXNotificationCenterPanel" : nil },
            identifier: { _ in nil },
            children: { [] }
        )
        XCTAssertFalse(NotificationPanelDetection.isPanelWindow(legacyNamedWindow))
    }

    func testBannerSubroleConstantMatchesWatcherExpectations() {
        XCTAssertEqual(
            NotificationPanelDetection.bannerSubroles,
            ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]
        )
    }
}
