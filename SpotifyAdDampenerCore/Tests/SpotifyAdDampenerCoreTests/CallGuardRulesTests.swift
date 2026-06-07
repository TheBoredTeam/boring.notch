import XCTest
@testable import SpotifyAdDampenerCore

final class CallGuardRulesTests: XCTestCase {
    func testKnownCallAppsWithMicActiveAreActive() {
        for bundleID in ["us.zoom.xos", "com.apple.FaceTime", "com.hnc.Discord"] {
            XCTAssertTrue(CallGuardRules.isCallActive(.init(runningBundleIDs: [bundleID], microphoneActive: true, screenCaptureActive: false, manualOverride: false)))
        }
    }

    func testBrowserWithoutMicOrCaptureIsInactive() {
        XCTAssertFalse(CallGuardRules.isCallActive(.init(runningBundleIDs: ["com.google.Chrome"], microphoneActive: false, screenCaptureActive: false, manualOverride: false)))
    }

    func testUnknownActiveMicSuppresses() {
        XCTAssertTrue(CallGuardRules.isCallActive(.init(runningBundleIDs: ["com.example.Unknown"], microphoneActive: true, screenCaptureActive: false, manualOverride: false)))
    }

    func testKnownCallAppIdleNoMicIsInactive() {
        XCTAssertFalse(CallGuardRules.isCallActive(.init(runningBundleIDs: ["us.zoom.xos"], microphoneActive: false, screenCaptureActive: false, manualOverride: false)))
    }

    func testManualOverrideIsActive() {
        XCTAssertTrue(CallGuardRules.isCallActive(.init(runningBundleIDs: [], microphoneActive: false, screenCaptureActive: false, manualOverride: true)))
    }
}
