//
//  PlaybackTimeTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class PlaybackTimeTests: XCTestCase {
    func testFormatsUnderAnHour() {
        XCTAssertEqual(PlaybackTime.string(from: 0), "0:00")
        XCTAssertEqual(PlaybackTime.string(from: 9), "0:09")
        XCTAssertEqual(PlaybackTime.string(from: 61), "1:01")
        XCTAssertEqual(PlaybackTime.string(from: 599), "9:59")
    }

    func testFormatsOverAnHour() {
        XCTAssertEqual(PlaybackTime.string(from: 3600), "1:00:00")
        XCTAssertEqual(PlaybackTime.string(from: 3661), "1:01:01")
    }

    func testNonFiniteIsPlaceholder() {
        XCTAssertEqual(PlaybackTime.string(from: .infinity), "--:--")
        XCTAssertEqual(PlaybackTime.string(from: .nan), "--:--")
    }

    func testNegativeClampsToZero() {
        // Previously rendered as "-0:-5" — the guard covered isFinite but not sign.
        XCTAssertEqual(PlaybackTime.string(from: -5), "0:00")
    }
}
