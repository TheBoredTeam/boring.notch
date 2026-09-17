//
//  SystemMetricsTests.swift
//  boringNotchTests
//
//  Covers the arithmetic behind the system monitor: counter deltas and the
//  edge cases that make them lie (wrapped counters, interfaces coming and
//  going, a racy VM sample), plus the byte/rate formatting split.
//

import XCTest

@testable import boringNotch

final class SystemMetricsTests: XCTestCase {

    // MARK: - CPU

    func testCPUUsageIsBusyTicksOverTotalTicks() throws {
        let previous = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let current = CPUTicks(user: 200, system: 100, idle: 1700, nice: 0)

        let usage = try XCTUnwrap(CPUUsage.between(previous: previous, current: current))

        XCTAssertEqual(usage.load, 0.15, accuracy: 0.0001)
        XCTAssertEqual(usage.userLoad, 0.10, accuracy: 0.0001)
        XCTAssertEqual(usage.systemLoad, 0.05, accuracy: 0.0001)
    }

    func testCPUUsageCountsNiceTimeAsBusy() throws {
        let previous = CPUTicks.zero
        let current = CPUTicks(user: 0, system: 0, idle: 50, nice: 50)

        let usage = try XCTUnwrap(CPUUsage.between(previous: previous, current: current))

        XCTAssertEqual(usage.load, 0.5, accuracy: 0.0001)
        XCTAssertEqual(usage.userLoad, 0.5, accuracy: 0.0001, "nice time is user time")
        XCTAssertEqual(usage.systemLoad, 0, accuracy: 0.0001)
    }

    /// A core coming online or offline between samples makes the summed
    /// counters move backwards. There is no sensible usage figure for that
    /// interval, and inventing one would show a spike that never happened.
    func testCPUUsageRejectsBackwardsCounters() {
        let low = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let high = CPUTicks(user: 200, system: 100, idle: 1700, nice: 0)

        XCTAssertNil(CPUUsage.between(previous: high, current: low))
    }

    func testCPUUsageRejectsEmptyInterval() {
        let ticks = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        XCTAssertNil(CPUUsage.between(previous: ticks, current: ticks))
    }

    /// The kernel hands these back as `integer_t` (Int32) even though they are
    /// unsigned, so an uptime long enough to pass 2^31 used to read as
    /// negative. The sampler reinterprets the bit pattern; this pins the
    /// arithmetic that consumes it.
    func testCPUUsageHandlesCountersPastSignedInt32Range() throws {
        let previous = CPUTicks(user: 4_000_000_000, system: 0, idle: 4_000_000_000, nice: 0)
        let current = CPUTicks(user: 4_000_000_100, system: 0, idle: 4_000_000_300, nice: 0)

        let usage = try XCTUnwrap(CPUUsage.between(previous: previous, current: current))

        XCTAssertEqual(usage.load, 0.25, accuracy: 0.0001)
    }

    // MARK: - Memory

    private let pageSize: UInt64 = 16384
    private let sixteenGigabytes: UInt64 = 17_179_869_184

    private func pages(
        active: UInt64 = 0, wired: UInt64 = 0, compressed: UInt64 = 0, purgeable: UInt64 = 0
    ) -> MemoryPageCounts {
        MemoryPageCounts(
            active: active, inactive: 0, wired: wired, compressed: compressed,
            purgeable: purgeable, speculative: 0, free: 0
        )
    }

    func testMemoryUsedExcludesPurgeableAndCachedPages() {
        let usage = MemoryUsage(
            pages: pages(active: 200_000, wired: 150_000, compressed: 50_000, purgeable: 20_000),
            pageSize: pageSize,
            totalBytes: sixteenGigabytes,
            pressure: .normal
        )

        XCTAssertEqual(usage.appBytes, 180_000 * pageSize, "app memory drops purgeable pages")
        XCTAssertEqual(usage.usedBytes, 380_000 * pageSize, "used = app + wired + compressed")
        XCTAssertEqual(usage.wiredBytes, 150_000 * pageSize)
        XCTAssertEqual(usage.compressedBytes, 50_000 * pageSize)
    }

    /// `active` and `purgeable` are read from the same struct but describe
    /// overlapping sets; a sample taken mid-reclaim can show more purgeable
    /// than active. Unsigned subtraction there would trap.
    func testMemoryAppBytesSaturatesWhenPurgeableExceedsActive() {
        let usage = MemoryUsage(
            pages: pages(active: 10, purgeable: 999),
            pageSize: pageSize,
            totalBytes: sixteenGigabytes,
            pressure: .normal
        )

        XCTAssertEqual(usage.appBytes, 0)
    }

    func testMemoryUsedIsClampedToPhysicalTotal() {
        let usage = MemoryUsage(
            pages: pages(active: 99_999_999),
            pageSize: pageSize,
            totalBytes: sixteenGigabytes,
            pressure: .normal
        )

        XCTAssertEqual(usage.usedBytes, sixteenGigabytes)
        XCTAssertEqual(usage.fraction, 1.0, accuracy: 0.0001)
    }

    func testMemoryFractionIsZeroWithoutATotal() {
        let usage = MemoryUsage(
            usedBytes: 1000, totalBytes: 0, wiredBytes: 0,
            compressedBytes: 0, appBytes: 0, pressure: .normal
        )

        XCTAssertEqual(usage.fraction, 0, "no divide-by-zero NaN reaches the gauge")
    }

    func testMemoryPressureLevelMapping() {
        XCTAssertEqual(MemoryPressureLevel(rawSysctlValue: 1), .normal)
        XCTAssertEqual(MemoryPressureLevel(rawSysctlValue: 2), .warning)
        XCTAssertEqual(MemoryPressureLevel(rawSysctlValue: 4), .critical)
        XCTAssertEqual(MemoryPressureLevel(rawSysctlValue: 3), .normal, "undocumented values fall back")
        XCTAssertEqual(MemoryPressureLevel(rawSysctlValue: 0), .normal)
    }

    // MARK: - Network

    func testNetworkThroughputDividesDeltaByInterval() {
        let throughput = NetworkThroughput.between(
            previous: NetworkByteCounts(received: 1_000, sent: 500),
            current: NetworkByteCounts(received: 3_000, sent: 1_500),
            interval: 2
        )

        XCTAssertEqual(throughput.downloadBytesPerSecond, 1_000, accuracy: 0.0001)
        XCTAssertEqual(throughput.uploadBytesPerSecond, 500, accuracy: 0.0001)
    }

    /// Turning Wi-Fi off, connecting a VPN or unplugging a dock changes which
    /// interfaces exist, so the summed counters restart from a lower number.
    /// That must read as "no traffic this interval", not as a burst.
    func testNetworkThroughputTreatsCounterResetAsIdle() {
        let throughput = NetworkThroughput.between(
            previous: NetworkByteCounts(received: 9_000, sent: 9_000),
            current: NetworkByteCounts(received: 10, sent: 10),
            interval: 2
        )

        XCTAssertEqual(throughput, .zero)
    }

    func testNetworkThroughputRejectsNonPositiveInterval() {
        let counts = NetworkByteCounts(received: 10, sent: 10)
        XCTAssertEqual(NetworkThroughput.between(previous: .zero, current: counts, interval: 0), .zero)
        XCTAssertEqual(NetworkThroughput.between(previous: .zero, current: counts, interval: -1), .zero)
    }

    // MARK: - Disk

    func testDiskUsage() {
        let disk = DiskUsage(usedBytes: 790, totalBytes: 1_000)

        XCTAssertEqual(disk.availableBytes, 210)
        XCTAssertEqual(disk.fraction, 0.79, accuracy: 0.0001)
    }

    func testDiskUsageWithoutCapacityIsEmptyRatherThanNaN() {
        let disk = DiskUsage(usedBytes: 10, totalBytes: 0)

        XCTAssertEqual(disk.fraction, 0)
        XCTAssertEqual(disk.availableBytes, 0)
    }

    // MARK: - Wi-Fi

    func testWiFiQualitySpansTheUsableDBmRange() {
        XCTAssertEqual(WiFiSignal(rssi: -50, ssid: nil).quality, 1.0, accuracy: 0.0001)
        XCTAssertEqual(WiFiSignal(rssi: -70, ssid: nil).quality, 0.5, accuracy: 0.0001)
        XCTAssertEqual(WiFiSignal(rssi: -90, ssid: nil).quality, 0.0, accuracy: 0.0001)
    }

    func testWiFiQualityClampsOutsideTheRange() {
        XCTAssertEqual(WiFiSignal(rssi: -10, ssid: nil).quality, 1.0, accuracy: 0.0001)
        XCTAssertEqual(WiFiSignal(rssi: -120, ssid: nil).quality, 0.0, accuracy: 0.0001)
    }

    func testWiFiBars() {
        XCTAssertEqual(WiFiSignal(rssi: -88, ssid: nil).bars, 0)
        XCTAssertEqual(WiFiSignal(rssi: -80, ssid: nil).bars, 1)
        XCTAssertEqual(WiFiSignal(rssi: -70, ssid: nil).bars, 2)
        XCTAssertEqual(WiFiSignal(rssi: -50, ssid: nil).bars, 3)
    }

    // MARK: - Battery health

    func testServiceRecommendedThreshold() {
        XCTAssertTrue(BatteryHealth(maximumCapacityPercent: 79.9).isServiceRecommended)
        XCTAssertFalse(BatteryHealth(maximumCapacityPercent: 80).isServiceRecommended)
        XCTAssertFalse(BatteryHealth(maximumCapacityPercent: 100).isServiceRecommended)
    }
}
