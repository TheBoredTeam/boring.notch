//
//  ClosedMusicActivityContentTests.swift
//  boringNotchTests
//

import XCTest
@testable import boringNotch

final class ClosedMusicActivityContentTests: XCTestCase {
    func testHidesDecorativeContentAndReservesNoSideSpaceBelowMinimumHeight() {
        XCTAssertFalse(ClosedMusicActivityContent.shouldDisplay(at: 23))
        XCTAssertFalse(ClosedMusicActivityContent.shouldDisplay(at: 15))
        XCTAssertEqual(ClosedMusicActivityContent.additionalChinWidth(at: 23), 0)
        XCTAssertEqual(ClosedMusicActivityContent.additionalChinWidth(at: 15), 0)
    }

    func testDisplaysDecorativeContentAndReservesSpaceAtMinimumHeight() {
        XCTAssertTrue(ClosedMusicActivityContent.shouldDisplay(at: 24))
        XCTAssertGreaterThan(ClosedMusicActivityContent.additionalChinWidth(at: 24), 0)
    }
}
