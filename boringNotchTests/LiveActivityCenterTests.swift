// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import SwiftUI
import XCTest
@testable import boringNotch

@MainActor
final class LiveActivityCenterTests: XCTestCase {
    private let id = LiveActivityID(namespace: "org.example", name: "download")

    private func activity(_ id: LiveActivityID, priority: Int = 0) -> AnyNotchLiveActivity {
        AnyNotchLiveActivity(descriptor: LiveActivityDescriptor(id: id, priority: priority),
                             leading: { _ in Text("Download") }, trailing: { _ in Text("50%") })
    }

    func testEndReleasesRendererAndUpdateReactivatesSameOwner() throws {
        let center = LiveActivityCenter()
        let registration = try center.register(activity(id))
        XCTAssertNotNil(center.activity(for: id))
        registration.end()
        XCTAssertNil(center.activity(for: id))
        XCTAssertTrue(center.service.registeredIDs.contains(id))
        try registration.update(activity(id, priority: 5))
        XCTAssertEqual(center.activity(for: id)?.descriptor.priority, 5)
        registration.unregister()
        XCTAssertNil(center.activity(for: id))
        XCTAssertFalse(center.service.registeredIDs.contains(id))
    }

    func testOldTokenCannotEraseOrUpdateReplacementRenderer() throws {
        let center = LiveActivityCenter()
        let old = try center.register(activity(id))
        old.unregister()
        let replacement = try center.register(activity(id, priority: 7))
        old.end()
        old.unregister()
        XCTAssertThrowsError(try old.update(activity(id, priority: 50)))
        XCTAssertEqual(center.activity(for: id)?.descriptor.priority, 7)
        replacement.unregister()
    }

    func testDroppingTokenReleasesIdentityAndRenderer() async throws {
        let center = LiveActivityCenter()
        var registration: NotchActivityRegistration? = try center.register(activity(id))
        XCTAssertNotNil(registration)
        registration = nil
        // Both cleanup tasks are enqueued before this main-actor continuation.
        for _ in 0..<10 where center.service.registeredIDs.contains(id) || center.activity(for: id) != nil {
            await Task.yield()
        }
        XCTAssertNil(center.activity(for: id))
        XCTAssertFalse(center.service.registeredIDs.contains(id))
    }
}
