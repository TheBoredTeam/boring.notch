// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import XCTest
@testable import boringNotch

final class ExtensionActivityDescriptorTests: XCTestCase {
    func testWireContractUsesHostAssignedNamespaceAndBoundedRelevance() throws {
        let value = try JSONDecoder().decode(ExtensionActivitySnapshot.self, from: Data(
            #"{"activities":[{"id":"download-1","label":"Download","relevance":"timeSensitive","extra":"ignored"}]}"#.utf8))
        try value.validate()
        let descriptor = try XCTUnwrap(value.activities.first).hostDescriptor(namespace: "org.example.downloads")
        XCTAssertEqual(descriptor.id, LiveActivityID(namespace: "org.example.downloads", name: "download-1"))
        XCTAssertEqual(descriptor.presentation, .activity)
        XCTAssertLessThan(descriptor.priority, 100) // app notifications retain their priority
        XCTAssertEqual(descriptor.lifetime, .persistent)
        XCTAssertEqual(descriptor.displayScope, .all)
        XCTAssertEqual(descriptor.surface, .desktop)
    }

    func testWireIDsCannotEscapeTheirNamespaceAndSnapshotRejectsDuplicates() throws {
        for id in ["", "../music", "provider/music", "music\n", String(repeating: "x", count: 101)] {
            XCTAssertThrowsError(try ExtensionActivityDescriptor(id: id, label: "Example").validate())
        }
        let value = ExtensionActivityDescriptor(id: "same", label: "Example")
        XCTAssertThrowsError(try ExtensionActivitySnapshot(activities: [value, value]).validate())
        XCTAssertThrowsError(try ExtensionActivitySnapshot(activities: (0..<17).map {
            ExtensionActivityDescriptor(id: "item-\($0)", label: "Example")
        }).validate())
        XCTAssertNoThrow(try ExtensionActivitySnapshot(activities: []).validate())
    }

    func testInvalidDeadlinesLabelsAndDisplayScopesAreRejected() {
        XCTAssertThrowsError(try ExtensionActivityDescriptor(id: "timer", label: "").validate())
        XCTAssertThrowsError(try ExtensionActivityDescriptor(id: "timer", label: "Timer", expiresAt: .infinity).validate())
        XCTAssertThrowsError(try ExtensionActivityDescriptor(id: "timer", label: "Timer", displays: [""]).validate())
        let value = ExtensionActivityDescriptor(id: "timer", label: "Timer", expiresAt: 42, displays: ["display-a"])
        let descriptor = value.hostDescriptor(namespace: "org.example.timer")
        XCTAssertEqual(descriptor.lifetime, .until(Date(timeIntervalSince1970: 42)))
        XCTAssertEqual(descriptor.displayScope, .displays(["display-a"]))
    }

    func testLockedSurfaceIsExplicitAndUnknownSurfaceFailsClosed() throws {
        let value = try JSONDecoder().decode(ExtensionActivityDescriptor.self, from: Data(
            #"{"id":"badge","label":"Status","surface":"lockScreen"}"#.utf8))
        try value.validate()
        XCTAssertEqual(value.hostDescriptor(namespace: "org.example.status").surface, .lockScreen)
        XCTAssertThrowsError(try JSONDecoder().decode(ExtensionActivityDescriptor.self, from: Data(
            #"{"id":"badge","label":"Status","surface":"everywhere"}"#.utf8)))
    }
}
