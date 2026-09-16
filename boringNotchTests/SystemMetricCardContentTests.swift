//
//  SystemMetricCardContentTests.swift
//  boringNotchTests
//
//  Covers what each monitor card actually says — including the cases where
//  the honest answer is "no reading" rather than a confident zero.
//

import XCTest

@testable import boringNotch

final class SystemMetricCardContentTests: XCTestCase {

    private let sixteenGigabytes: UInt64 = 17_179_869_184

    private func snapshot() -> SystemMetricsSnapshot {
        var snapshot = SystemMetricsSnapshot()
        snapshot.cpu = CPUUsage(load: 0.49, userLoad: 0.30, systemLoad: 0.19)
        snapshot.memory = MemoryUsage(
            usedBytes: 13_345_000_000,
            totalBytes: sixteenGigabytes,
            wiredBytes: 0, compressedBytes: 0, appBytes: 0,
            pressure: .normal
        )
        snapshot.disk = DiskUsage(usedBytes: 790_000_000_000, totalBytes: 1_000_000_000_000)
        snapshot.network = NetworkThroughput(downloadBytesPerSecond: 1_200_000, uploadBytesPerSecond: 240_000)
        snapshot.wifi = WiFiSignal(rssi: -52, ssid: "Home")
        return snapshot
    }

    private let battery = BatterySummary(
        chargePercent: 30, isCharging: false, isPluggedIn: false,
        minutesRemaining: 41, health: BatteryHealth(maximumCapacityPercent: 92)
    )

    private func content(
        _ kind: SystemMetricKind,
        snapshot: SystemMetricsSnapshot? = nil,
        battery: BatterySummary? = nil
    ) -> SystemMetricCardContent {
        SystemMetricCardBuilder.content(
            for: kind,
            snapshot: snapshot ?? self.snapshot(),
            battery: battery ?? self.battery,
            coreCount: 8
        )
    }

    // MARK: - CPU

    func testCPUShowsOneDecimalAndCoreCount() {
        let card = content(.cpu)

        XCTAssertEqual(card.value, "49.0")
        XCTAssertEqual(card.unit, "%")
        XCTAssertTrue(card.subtitle.contains("8"), "subtitle was \(card.subtitle)")
        XCTAssertFalse(card.isIndeterminate)
    }

    /// Usage needs two tick samples. Until the second one lands the card has
    /// nothing true to say, and "0.0%" would read as an idle Mac.
    func testCPUBeforeSecondSampleShowsNoReading() {
        var snapshot = self.snapshot()
        snapshot.cpu = nil

        let card = content(.cpu, snapshot: snapshot)

        XCTAssertTrue(card.isIndeterminate)
        XCTAssertEqual(card.value, SystemMetricFormatter.unavailable)
        XCTAssertEqual(card.fraction, 0)
    }

    // MARK: - Memory

    /// macOS calls 17,179,869,184 bytes "16 GB". Splitting on decimal steps
    /// would render a 16 GB Mac as having 17.18 GB of RAM.
    func testMemoryUsesBinaryUnitsSoASixteenGigMacReadsAsSixteen() {
        let card = content(.memory)

        XCTAssertEqual(card.unit, "GB")
        XCTAssertTrue(card.subtitle.contains("16 GB"), "subtitle was \(card.subtitle)")
    }

    func testMemoryWithoutATotalIsIndeterminate() {
        var snapshot = self.snapshot()
        snapshot.memory = nil
        XCTAssertTrue(content(.memory, snapshot: snapshot).isIndeterminate)

        snapshot.memory = MemoryUsage(
            usedBytes: 0, totalBytes: 0, wiredBytes: 0,
            compressedBytes: 0, appBytes: 0, pressure: .normal
        )
        XCTAssertTrue(content(.memory, snapshot: snapshot).isIndeterminate, "a zero total is also no reading")
    }

    // MARK: - Disk

    /// Storage is reported in decimal GB everywhere else on the system, so
    /// "210 GB free" has to match Finder rather than Activity Monitor.
    func testDiskUsesDecimalUnitsAndReportsFreeSpace() {
        let card = content(.disk)

        XCTAssertEqual(card.value, "79")
        XCTAssertEqual(card.unit, "%")
        XCTAssertTrue(card.subtitle.contains("210 GB"), "subtitle was \(card.subtitle)")
    }

    // MARK: - Network

    func testNetworkShowsDownloadAsHeadlineAndUploadAsSubtitle() {
        let card = content(.network)

        XCTAssertEqual(card.value, "1.2")
        XCTAssertEqual(card.unit, "MB/s")
        XCTAssertTrue(card.subtitle.contains("240 KB/s"), "subtitle was \(card.subtitle)")
    }

    func testNetworkBeforeSecondSampleShowsNoReading() {
        var snapshot = self.snapshot()
        snapshot.network = nil

        let card = content(.network, snapshot: snapshot)

        XCTAssertTrue(card.isIndeterminate)
        XCTAssertEqual(card.value, SystemMetricFormatter.unavailable)
    }

    func testNetworkRingSaturatesAtFullScale() {
        var snapshot = self.snapshot()
        snapshot.network = NetworkThroughput(
            downloadBytesPerSecond: SystemMetricCardBuilder.networkRingFullScaleBytesPerSecond * 10,
            uploadBytesPerSecond: 0
        )

        XCTAssertEqual(content(.network, snapshot: snapshot).fraction, 1.0, accuracy: 0.0001)
    }

    // MARK: - Battery

    func testBatteryLeadsWithHealthWhenKnown() {
        let card = content(.battery)

        XCTAssertEqual(card.value, "30")
        XCTAssertEqual(card.unit, "%")
        XCTAssertTrue(card.subtitle.contains("92"), "subtitle was \(card.subtitle)")
    }

    /// Below 80% of design capacity Apple shows "Service Recommended"; echoing
    /// that wording is more useful than the bare number.
    func testBatteryBelowServiceThresholdReplacesTheNumber() {
        let worn = BatterySummary(
            chargePercent: 55, isCharging: false, isPluggedIn: false,
            minutesRemaining: 0, health: BatteryHealth(maximumCapacityPercent: 71)
        )

        XCTAssertFalse(content(.battery, battery: worn).subtitle.contains("71"))
    }

    func testBatteryFallsBackToTimeRemainingWithoutHealth() {
        let noHealth = BatterySummary(
            chargePercent: 30, isCharging: false, isPluggedIn: false,
            minutesRemaining: 41, health: nil
        )

        XCTAssertTrue(content(.battery, battery: noHealth).subtitle.contains("41"))
    }

    func testDesktopMacWithoutABatteryIsIndeterminate() {
        XCTAssertTrue(content(.battery, battery: .unknown).isIndeterminate)
    }

    // MARK: - Wi-Fi

    func testWiFiShowsRSSIAndNetworkName() {
        let card = content(.wifi)

        XCTAssertEqual(card.value, "-52")
        XCTAssertEqual(card.subtitle, "Home")
    }

    /// macOS 14+ hides the SSID unless Location Services is granted. The card
    /// still has a signal reading, so it describes the quality instead of
    /// leaving the line blank.
    func testWiFiWithoutSSIDFallsBackToAQualityDescription() {
        var snapshot = self.snapshot()
        snapshot.wifi = WiFiSignal(rssi: -52, ssid: nil)

        let card = content(.wifi, snapshot: snapshot)

        XCTAssertFalse(card.subtitle.isEmpty)
        XCTAssertEqual(card.value, "-52")
    }

    func testNoWiFiRadioIsIndeterminate() {
        var snapshot = self.snapshot()
        snapshot.wifi = nil

        XCTAssertTrue(content(.wifi, snapshot: snapshot).isIndeterminate)
    }

    // MARK: - Metric catalogue

    /// `displayOrder` is hand-written so that reordering the enum can't
    /// reshuffle the user's notch. The cost of that is that a new case can be
    /// forgotten here and silently never render — this is the guard.
    func testDisplayOrderCoversEveryMetric() {
        XCTAssertEqual(
            Set(SystemMetricKind.displayOrder),
            Set(SystemMetricKind.allCases),
            "a metric is missing from displayOrder and would never appear in the grid"
        )
        XCTAssertEqual(
            SystemMetricKind.displayOrder.count,
            SystemMetricKind.allCases.count,
            "displayOrder lists a metric twice"
        )
    }

    func testEveryMetricProducesContentWithoutCrashingOnAnEmptySnapshot() {
        for kind in SystemMetricKind.allCases {
            let card = SystemMetricCardBuilder.content(
                for: kind,
                snapshot: SystemMetricsSnapshot(),
                battery: .unknown,
                coreCount: 0
            )
            XCTAssertTrue(card.isIndeterminate, "\(kind) should report no reading from an empty snapshot")
            XCTAssertEqual(card.value, SystemMetricFormatter.unavailable, "\(kind)")
            XCTAssertFalse(card.fraction.isNaN, "\(kind) produced a NaN ring fraction")
        }
    }

    // MARK: - Formatting

    func testDurationString() {
        XCTAssertEqual(SystemMetricCardBuilder.durationString(minutes: 41), "41m")
        XCTAssertEqual(SystemMetricCardBuilder.durationString(minutes: 80), "1h 20m")
        XCTAssertEqual(SystemMetricCardBuilder.durationString(minutes: 120), "2h")
        XCTAssertEqual(SystemMetricCardBuilder.durationString(minutes: 0), "0m")
        XCTAssertEqual(SystemMetricCardBuilder.durationString(minutes: -5), "0m", "negatives clamp")
    }

    func testSplitBytesBinaryVersusDecimal() {
        let memory = SystemMetricCardBuilder.splitBytes(sixteenGigabytes, base: .binary, fractionDigits: 0)
        XCTAssertEqual("\(memory.value) \(memory.unit)", "16 GB")

        let disk = SystemMetricCardBuilder.splitBytes(500_000_000_000, base: .decimal, fractionDigits: 0)
        XCTAssertEqual("\(disk.value) \(disk.unit)", "500 GB")
    }

    func testSplitRateDropsDecimalsWhereTheyWouldBeNoise() {
        let fast = SystemMetricCardBuilder.splitRate(1_200_000)
        XCTAssertEqual("\(fast.value) \(fast.unit)", "1.2 MB/s")

        let medium = SystemMetricCardBuilder.splitRate(240_000)
        XCTAssertEqual("\(medium.value) \(medium.unit)", "240 KB/s", "no decimal at KB")

        let idle = SystemMetricCardBuilder.splitRate(0)
        XCTAssertEqual(idle.value, "0")

        let negative = SystemMetricCardBuilder.splitRate(-5)
        XCTAssertEqual(negative.value, "0", "a negative rate is impossible; clamp rather than render it")
    }

    func testPercentFormatterRoundsAndClamps() {
        XCTAssertEqual(SystemMetricFormatter.percent(0.494), "49%")
        XCTAssertEqual(SystemMetricFormatter.percent(0.495), "50%")
        XCTAssertEqual(SystemMetricFormatter.percent(1.7), "100%")
        XCTAssertEqual(SystemMetricFormatter.percent(-1), "0%")
    }
}
