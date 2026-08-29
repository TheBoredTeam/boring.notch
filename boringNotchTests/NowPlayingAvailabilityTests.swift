//
//  NowPlayingAvailabilityTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class NowPlayingAvailabilityTests: XCTestCase {
    func testAvailableIsSelectable() {
        XCTAssertTrue(NowPlayingAvailability.available.isSelectable)
        XCTAssertFalse(NowPlayingAvailability.available.usesTemporaryFallback)
    }

    func testSetupFailureIsNotRetriable() {
        let availability = NowPlayingAvailability.unavailable(.setup)

        XCTAssertEqual(availability.failure, .setup)
        XCTAssertFalse(availability.offersManualRetry)
        XCTAssertFalse(availability.usesTemporaryFallback)
    }

    func testProbeFailureOffersManualRetry() {
        let availability = NowPlayingAvailability.unavailable(.probe)

        XCTAssertEqual(availability.failure, .probe)
        XCTAssertTrue(availability.offersManualRetry)
        XCTAssertTrue(availability.usesTemporaryFallback)
    }

    func testRuntimeFailureDoesNotOfferManualRetry() {
        let availability = NowPlayingAvailability.unavailable(.runtime)

        XCTAssertEqual(availability.failure, .runtime)
        XCTAssertFalse(availability.offersManualRetry)
        XCTAssertTrue(availability.usesTemporaryFallback)
    }
}
