//
//  NotchUIEventTests.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Smoke tests for the seams introduced during the architecture remediation.
//

import XCTest
import Combine
@testable import boringNotch

final class NotchUIEventTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    /// Managers publish; the presenter subscribes — the seam that replaced
    /// direct manager->coordinator calls. This is the contract.
    func testSneakPeekEventDeliversPayload() {
        let expectation = expectation(description: "event delivered")
        NotchUIEventBus.events
            .sink { event in
                guard case .sneakPeek(let type, let value, let icon, _, let uuid, _, _) = event else {
                    XCTFail("unexpected event")
                    return
                }
                XCTAssertEqual(type, .volume)
                XCTAssertEqual(value, 0.5, accuracy: 0.0001)
                XCTAssertEqual(icon, "speaker.wave.2")
                XCTAssertNil(uuid)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        NotchUIEventBus.events.send(.sneakPeek(type: .volume, value: 0.5, icon: "speaker.wave.2"))
        waitForExpectations(timeout: 1.0)
    }

    func testExpandingViewEventDeliversType() {
        let expectation = expectation(description: "expanding event delivered")
        NotchUIEventBus.events
            .sink { event in
                guard case .expandingView(let type) = event else {
                    XCTFail("unexpected event")
                    return
                }
                XCTAssertEqual(type, .battery)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        NotchUIEventBus.events.send(.expandingView(type: .battery))
        waitForExpectations(timeout: 1.0)
    }

    func testNotificationPeekLandsInLaneWithPayload() {
        let expectation = expectation(description: "notification peek event carries payload")
        NotchUIEventBus.events
            .sink { event in
                if case .sneakPeek(let type, _, _, _, _, _, let payload) = event,
                   type == .notification {
                    XCTAssertEqual(payload?.title ?? "", "Sender")
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        NotchUIEventBus.events.send(.sneakPeek(
            type: .notification, value: 0,
            payload: NotificationPeekPayload(
                appName: "WhatsApp", title: "Sender", body: "hello",
                bundleID: "net.whatsapp.WhatsApp")))

        waitForExpectations(timeout: 1.0)
    }

    /// Full chain: peek event -> toggleSneakPeek routing -> dedicated lane state.
    func testNotificationPeekEndsInLane() async throws {
        NotchUIEventBus.events.send(.sneakPeek(
            type: .notification, value: 0, duration: 3.0,
            payload: NotificationPeekPayload(
                appName: "WhatsApp", title: "Sender", body: "hello",
                bundleID: "net.whatsapp.WhatsApp")))

        try await Task.sleep(for: .milliseconds(500))

        let visible = await MainActor.run {
            BoringViewCoordinator.shared.notificationPeekStates.values.first { $0.show }
        }
        XCTAssertNotNil(visible, "notification peek should be visible in its lane")
        XCTAssertEqual(visible?.payload?.title ?? "", "Sender")
        if let uuid = visible?.targetScreenUUID {
            await MainActor.run {
                BoringViewCoordinator.shared.notificationPeekStates[uuid]?.show = false
            }
        }
    }
}

final class MediaAppBundleIDTests: XCTestCase {
    func testBundleIDsAreDistinctAndWellFormed() {
        let ids = [
            MediaAppBundleID.appleMusic,
            MediaAppBundleID.spotify,
            MediaAppBundleID.youTubeMusic,
        ]
        XCTAssertEqual(ids.count, Set(ids).count, "bundle IDs must be unique")
        for id in ids {
            XCTAssertFalse(id.isEmpty)
            XCTAssertTrue(id.contains("."), "malformed bundle id: \(id)")
        }
    }
}

final class PlaybackStateTests: XCTestCase {
    func testEquatableIgnoresVolatileFields() {
        var a = PlaybackState(bundleIdentifier: MediaAppBundleID.spotify, isPlaying: true)
        a.title = "Track"
        a.currentTime = 42

        var b = a
        // Volatile/monitor-side fields that must not defeat `==`:
        // volume, playbackRate and lastUpdated are intentionally excluded.
        b.volume = 0.9
        b.playbackRate = 0.75
        b.lastUpdated = Date()

        XCTAssertEqual(a, b)
    }

    func testEquatableTracksUserVisibleFields() {
        var a = PlaybackState(bundleIdentifier: MediaAppBundleID.spotify, isPlaying: true)
        a.title = "Track"

        var b = a
        b.isFavorite = true
        XCTAssertNotEqual(a, b, "isFavorite is user-visible and must be compared")

        b = a
        b.currentTime += 1
        XCTAssertNotEqual(a, b, "position changes must be visible to == to drive UI updates")
    }
}
