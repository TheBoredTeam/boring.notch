//
//  AudioProcessObserverTests.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import XCTest
@testable import boringNotch

final class AudioProcessObserverTests: XCTestCase {
    func testExactBundleIdentifiersIgnoreCase() {
        XCTAssertTrue(matches("com.spotify.client", targets: ["COM.SPOTIFY.CLIENT"]))
        XCTAssertFalse(matches("com.spotify.client.beta", targets: ["com.spotify.client"]))
        XCTAssertFalse(matches("com.spotify.client", targets: []))
        XCTAssertFalse(matches("", targets: [""]))
    }

    func testLateChromiumHelperMatchesItsApplication() {
        XCTAssertTrue(matches("com.google.Chrome.helper", targets: ["com.google.Chrome"]))
        XCTAssertTrue(matches("com.google.Chrome.helper.audio", targets: ["com.google.Chrome"]))
        XCTAssertTrue(matches("COM.GOOGLE.CHROME.HELPER.renderer", targets: ["com.google.Chrome"]))
    }

    func testCaptureHelperIdentifiesSiblingHelpersOnlyWithinItsApplication() {
        XCTAssertTrue(matches("com.google.Chrome.helper.audio", targets: ["com.google.Chrome.helper.renderer"]))
        XCTAssertTrue(matches("com.google.Chrome", targets: ["com.google.Chrome.helper"]))
        XCTAssertFalse(matches("com.microsoft.edgemac.helper.audio", targets: ["com.google.Chrome.helper"]))
    }

    func testHelperMatchingRequiresACompleteBundleComponent() {
        XCTAssertFalse(matches("com.google.ChromeBeta.helper", targets: ["com.google.Chrome"]))
        XCTAssertFalse(matches("com.google.Chrome.helperish", targets: ["com.google.Chrome"]))
        XCTAssertFalse(matches("com.google.Chrome.evil.helper", targets: ["com.google.Chrome"]))
    }

    func testSharedWebKitRequiresDisplayAppAssociation() {
        XCTAssertFalse(matches("com.apple.WebKit.WebContent", targets: ["com.apple.Safari"]))
        XCTAssertFalse(matches("com.apple.WebKit.WebContent", targets: ["com.apple.WebKit.WebContent"]))
        XCTAssertTrue(matches("com.apple.WebKit.WebContent", targets: ["com.apple.Safari"], associated: true))
        XCTAssertTrue(matches("COM.APPLE.WEBKIT.GPU", targets: ["com.example.WebApp"], associated: true))
    }

    func testUnrelatedApplicationsCannotMatchByAssociationAlone() {
        XCTAssertFalse(matches("com.spotify.client", targets: ["com.google.Chrome"], associated: true))
    }

    func testUniquelyAttributedHelpersDoNotRequireProcessAssociationLookup() {
        var checkedAssociation = false
        func association() -> Bool {
            checkedAssociation = true
            return false
        }
        XCTAssertTrue(AudioProcessObserver.isCaptureTarget(
            bundleIdentifier: "com.google.Chrome.helper.audio",
            bundleIDs: ["com.google.Chrome"],
            belongsToDisplayApp: association()
        ))
        XCTAssertFalse(checkedAssociation)
    }

    private func matches(_ bundleID: String, targets: Set<String>, associated: Bool = false) -> Bool {
        AudioProcessObserver.isCaptureTarget(
            bundleIdentifier: bundleID,
            bundleIDs: targets,
            belongsToDisplayApp: associated
        )
    }
}
