import AppKit
import Defaults
import XCTest
@testable import boringNotch

@MainActor
final class MediaKeyReleaseTests: XCTestCase {
    private func withInterceptor(_ body: (MediaKeyInterceptor) throws -> Void) rethrows {
        let action = Defaults[.optionKeyAction]
        let volumeSource = Defaults[.osdVolumeSource]
        let brightnessSource = Defaults[.osdBrightnessSource]
        let interceptor = MediaKeyInterceptor.shared
        interceptor.stop()
        // Option + No Action consumes keys without changing real audio/display settings.
        Defaults[.optionKeyAction] = .none
        Defaults[.osdVolumeSource] = .builtin
        Defaults[.osdBrightnessSource] = .builtin
        defer {
            interceptor.stop()
            Defaults[.optionKeyAction] = action
            Defaults[.osdVolumeSource] = volumeSource
            Defaults[.osdBrightnessSource] = brightnessSource
        }
        try body(interceptor)
    }

    private func event(_ key: Int, down: Bool, modifiers: NSEvent.ModifierFlags = []) throws -> CGEvent {
        let event = try XCTUnwrap(NSEvent.otherEvent(with: .systemDefined,
            location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
            context: nil, subtype: 8, data1: (key << 16) | ((down ? 0xA : 0xB) << 8), data2: 0))
        return try XCTUnwrap(event.cgEvent)
    }

    func testConsumedPressAlsoConsumesReleaseAfterModifierIsReleased() throws {
        try withInterceptor { interceptor in
            XCTAssertNil(interceptor.handleEvent(try event(0, down: true, modifiers: .option)))
            XCTAssertNil(interceptor.handleEvent(try event(0, down: false)))
        }
    }

    func testUnmatchedAndUnknownKeyReleasesPassThrough() throws {
        try withInterceptor { interceptor in
            XCTAssertNotNil(interceptor.handleEvent(try event(0, down: false)))
            XCTAssertNotNil(interceptor.handleEvent(try event(16, down: true, modifiers: .option)))
            XCTAssertNotNil(interceptor.handleEvent(try event(16, down: false)))
        }
    }

    func testAutoRepeatNeedsOnlyOneRelease() throws {
        try withInterceptor { interceptor in
            for _ in 0..<3 {
                XCTAssertNil(interceptor.handleEvent(try event(1, down: true, modifiers: .option)))
            }
            XCTAssertNil(interceptor.handleEvent(try event(1, down: false)))
            XCTAssertNotNil(interceptor.handleEvent(try event(1, down: false)))
        }
    }

    func testReleasesAreMatchedByKey() throws {
        try withInterceptor { interceptor in
            XCTAssertNil(interceptor.handleEvent(try event(0, down: true, modifiers: .option)))
            XCTAssertNil(interceptor.handleEvent(try event(1, down: true, modifiers: .option)))
            XCTAssertNil(interceptor.handleEvent(try event(0, down: false)))
            XCTAssertNil(interceptor.handleEvent(try event(1, down: false)))
        }
    }

    func testStopDiscardsPendingReleases() throws {
        try withInterceptor { interceptor in
            XCTAssertNil(interceptor.handleEvent(try event(0, down: true, modifiers: .option)))
            interceptor.stop()
            XCTAssertNotNil(interceptor.handleEvent(try event(0, down: false)))
        }
    }
}
