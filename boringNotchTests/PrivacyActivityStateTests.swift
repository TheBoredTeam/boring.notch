//
//  PrivacyActivityStateTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class PrivacyActivityStateTests: XCTestCase {

    // MARK: - Attribution

    /// Helper processes are what actually record; the user thinks of them as the app.
    func testFoldsHelperProcessesOntoTheirApp() {
        XCTAssertEqual(
            PrivacyAttribution.normalize(["com.google.Chrome.helper"]), ["com.google.Chrome"])
        XCTAssertEqual(
            PrivacyAttribution.normalize(["com.brave.Browser.helper"]), ["com.brave.Browser"])
    }

    /// Measured on a real machine: CoreSpeech starts recording alongside any app that does,
    /// and reporting it would read as a false alarm.
    func testDropsSystemListeners() {
        XCTAssertTrue(PrivacyAttribution.isExcluded("com.apple.CoreSpeech"))
        XCTAssertTrue(PrivacyAttribution.isExcluded("com.apple.Siri"))
        XCTAssertTrue(PrivacyAttribution.isExcluded("com.apple.controlcenter"))
        XCTAssertEqual(
            PrivacyAttribution.normalize(["com.apple.CoreSpeech", "us.zoom.xos"]), ["us.zoom.xos"])
    }

    /// Some audio processes report no bundle identifier at all.
    func testDropsEmptyBundleIdentifiers() {
        XCTAssertEqual(PrivacyAttribution.normalize(["", "   ", "us.zoom.xos"]), ["us.zoom.xos"])
    }

    /// A browser records from several helpers at once; the user should see one entry.
    func testCollapsesDuplicatesPreservingOrder() {
        XCTAssertEqual(
            PrivacyAttribution.normalize([
                "com.google.Chrome.helper", "com.google.Chrome", "us.zoom.xos",
                "com.google.Chrome.helper",
            ]),
            ["com.google.Chrome", "us.zoom.xos"])
    }

    func testOrdinaryAppsSurviveUntouched() {
        XCTAssertEqual(
            PrivacyAttribution.normalize(["us.zoom.xos", "com.apple.QuickTimePlayerX"]),
            ["us.zoom.xos", "com.apple.QuickTimePlayerX"])
    }

    // MARK: - Transitions

    private func usage(mic: Bool = false, camera: Bool = false) -> PrivacyUsage {
        PrivacyUsage(microphoneActive: mic, cameraActive: camera)
    }

    func testReportsStartAndStop() {
        var detector = PrivacyTransitionDetector()
        XCTAssertEqual(detector.update(usage(mic: true)), [.started(.microphone)])
        XCTAssertEqual(detector.update(usage(mic: false)), [.stopped(.microphone)])
    }

    /// The whole point: a long call must not keep producing activities.
    func testStaysQuietWhileNothingChanges() {
        var detector = PrivacyTransitionDetector()
        XCTAssertEqual(detector.update(usage(mic: true)), [.started(.microphone)])
        XCTAssertEqual(detector.update(usage(mic: true)), [])
        XCTAssertEqual(detector.update(usage(mic: true)), [])
        XCTAssertTrue(detector.isAnythingActive)
    }

    func testMicrophoneAndCameraAreTrackedIndependently() {
        var detector = PrivacyTransitionDetector()
        XCTAssertEqual(detector.update(usage(mic: true)), [.started(.microphone)])
        // Camera joining a call already using the microphone reports only the camera.
        XCTAssertEqual(detector.update(usage(mic: true, camera: true)), [.started(.camera)])
        XCTAssertEqual(detector.update(usage(mic: true, camera: false)), [.stopped(.camera)])
        XCTAssertEqual(detector.update(usage(mic: false)), [.stopped(.microphone)])
    }

    func testBothStartingAtOnceReportsBoth() {
        var detector = PrivacyTransitionDetector()
        XCTAssertEqual(
            detector.update(usage(mic: true, camera: true)),
            [.started(.microphone), .started(.camera)])
    }

    func testNothingHappeningProducesNoEvents() {
        var detector = PrivacyTransitionDetector()
        XCTAssertEqual(detector.update(usage()), [])
        XCTAssertFalse(detector.isAnythingActive)
    }

    func testActiveResourcesReflectsState() {
        XCTAssertEqual(usage(mic: true, camera: true).activeResources, [.microphone, .camera])
        XCTAssertEqual(usage(camera: true).activeResources, [.camera])
        XCTAssertTrue(usage().activeResources.isEmpty)
    }
}
