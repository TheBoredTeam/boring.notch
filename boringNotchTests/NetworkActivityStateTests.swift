//
//  NetworkActivityStateTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class NetworkActivityStateTests: XCTestCase {

    private func counters(_ rx: UInt64, _ tx: UInt64) -> InterfaceCounters {
        InterfaceCounters(received: rx, sent: tx)
    }

    func testComputesRateOverOneSecond() {
        let result = NetworkActivityState.throughput(
            from: counters(1_000, 500), to: counters(9_200, 1_900), over: 1)
        XCTAssertEqual(result.download, 8_200, accuracy: 0.001)
        XCTAssertEqual(result.upload, 1_400, accuracy: 0.001)
    }

    /// Samples never land exactly on the interval, so the elapsed time has to divide out.
    func testScalesByActualElapsedTime() {
        let result = NetworkActivityState.throughput(
            from: counters(0, 0), to: counters(4_000, 2_000), over: 2)
        XCTAssertEqual(result.download, 2_000, accuracy: 0.001)
        XCTAssertEqual(result.upload, 1_000, accuracy: 0.001)
    }

    /// A decrease means the interface was reset or swapped, not that traffic ran backwards.
    /// Subtracting would fabricate a spike of however much the old interface had counted.
    func testCounterResetReportsZeroRatherThanASpike() {
        let result = NetworkActivityState.throughput(
            from: counters(4_000_000_000, 2_000_000_000), to: counters(1_024, 512), over: 1)
        XCTAssertEqual(result.download, 0)
        XCTAssertEqual(result.upload, 0)
    }

    /// Each direction is judged on its own; one resetting must not zero the other.
    func testDirectionsAreIndependent() {
        let result = NetworkActivityState.throughput(
            from: counters(10_000, 5_000), to: counters(12_000, 100), over: 1)
        XCTAssertEqual(result.download, 2_000, accuracy: 0.001)
        XCTAssertEqual(result.upload, 0)
    }

    /// Two samples in the same instant would divide by zero.
    func testZeroOrNegativeIntervalIsSafe() {
        XCTAssertEqual(
            NetworkActivityState.throughput(from: counters(0, 0), to: counters(500, 500), over: 0),
            .zero)
        XCTAssertEqual(
            NetworkActivityState.throughput(from: counters(0, 0), to: counters(500, 500), over: -1),
            .zero)
    }

    func testIdleLinkReportsZero() {
        let result = NetworkActivityState.throughput(
            from: counters(5_000, 5_000), to: counters(5_000, 5_000), over: 1)
        XCTAssertEqual(result, .zero)
    }

    /// The 64-bit counters comfortably exceed what a 32-bit reading could hold, which is the
    /// reason for reading them from the routing table rather than from getifaddrs.
    func testHandlesValuesBeyond32Bits() {
        let start: UInt64 = 5_000_000_000  // past UInt32.max
        let result = NetworkActivityState.throughput(
            from: counters(start, start), to: counters(start + 1_048_576, start + 1_024), over: 1)
        XCTAssertEqual(result.download, 1_048_576, accuracy: 0.001)
        XCTAssertEqual(result.upload, 1_024, accuracy: 0.001)
    }

    // MARK: - Formatting

    func testFormatsRateWithUnitSuffix() {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        XCTAssertTrue(NetworkActivityState.formatRate(1_048_576, formatter: formatter).hasSuffix("/s"))
        XCTAssertTrue(NetworkActivityState.formatRate(0, formatter: formatter).hasSuffix("/s"))
    }

    /// A non-finite rate would otherwise crash the Int64 conversion.
    func testFormatsNonFiniteAndNegativeRatesSafely() {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        XCTAssertFalse(NetworkActivityState.formatRate(.nan, formatter: formatter).isEmpty)
        XCTAssertFalse(NetworkActivityState.formatRate(.infinity, formatter: formatter).isEmpty)
        XCTAssertFalse(NetworkActivityState.formatRate(-500, formatter: formatter).isEmpty)
    }
}
