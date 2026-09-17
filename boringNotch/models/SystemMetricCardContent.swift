//
//  SystemMetricCardContent.swift
//  boringNotch
//
//  Turns a metrics snapshot into the strings a monitor card displays.
//
//  This is the part of the system monitor most likely to be quietly wrong —
//  binary vs. decimal byte units, a rate before the second sample has landed,
//  a missing Wi-Fi radio — so it is pure, takes its inputs as plain values,
//  and is covered by tests rather than by squinting at a running notch.
//

import Foundation

/// Battery facts the card needs, passed in rather than read from
/// `BatteryStatusViewModel` so the builder stays testable.
struct BatterySummary: Equatable {
    var chargePercent: Double
    var isCharging: Bool
    var isPluggedIn: Bool
    /// Minutes to empty (discharging) or to full (charging). Zero means the
    /// system has no estimate yet, which is common for a few minutes after
    /// waking or plugging in.
    var minutesRemaining: Int
    var health: BatteryHealth?

    static let unknown = BatterySummary(
        chargePercent: 0, isCharging: false, isPluggedIn: false,
        minutesRemaining: 0, health: nil
    )
}

struct SystemMetricCardContent: Equatable {
    /// The large number. Never carries its unit — the unit is drawn smaller
    /// and baseline-aligned beside it.
    var value: String
    var unit: String?
    var subtitle: String
    /// Ring fill, 0...1.
    var fraction: Double
    /// True when there is no reading to show; the ring draws empty and the
    /// value is a dash.
    var isIndeterminate: Bool
}

enum SystemMetricCardBuilder {
    /// Full-scale download rate for the network ring, in bytes per second.
    ///
    /// 100 Mbit/s: fast enough that ordinary browsing stays low on the dial,
    /// slow enough that a large download visibly fills it. The ring is a
    /// relative sense of "how busy", not a calibrated instrument — the exact
    /// number is in the label right next to it.
    static let networkRingFullScaleBytesPerSecond: Double = 100_000_000 / 8

    static func content(
        for kind: SystemMetricKind,
        snapshot: SystemMetricsSnapshot,
        battery: BatterySummary,
        coreCount: Int
    ) -> SystemMetricCardContent {
        switch kind {
        case .cpu:
            return cpuContent(snapshot.cpu, coreCount: coreCount)
        case .memory:
            return memoryContent(snapshot.memory)
        case .battery:
            return batteryContent(battery)
        case .disk:
            return diskContent(snapshot.disk)
        case .network:
            return networkContent(snapshot.network)
        case .wifi:
            return wifiContent(snapshot.wifi)
        }
    }

    /// The shape every "we have nothing to show" card takes: empty ring, a
    /// dash where the number goes, and a subtitle that says why if it can.
    private static func noReading(subtitle: String = "") -> SystemMetricCardContent {
        SystemMetricCardContent(
            value: SystemMetricFormatter.unavailable,
            unit: nil,
            subtitle: subtitle,
            fraction: 0,
            isIndeterminate: true
        )
    }

    // MARK: - Per-metric

    private static func cpuContent(_ cpu: CPUUsage?, coreCount: Int) -> SystemMetricCardContent {
        // nil until a second tick sample lands — usage is a delta, so there is
        // genuinely no figure yet rather than a figure that happens to be zero.
        guard let cpu else {
            return noReading(subtitle: coreCount > 0 ? coreSubtitle(coreCount) : "")
        }
        // One decimal, matching Activity Monitor. Two would be false
        // precision on a value that moves every sample.
        return .init(
            value: decimalString(min(1, max(0, cpu.load)) * 100, fractionDigits: 1),
            unit: "%",
            subtitle: coreSubtitle(coreCount),
            fraction: cpu.load,
            isIndeterminate: false
        )
    }

    private static func memoryContent(_ memory: MemoryUsage?) -> SystemMetricCardContent {
        guard let memory, memory.totalBytes > 0 else { return noReading() }
        // Binary units: macOS calls 17,179,869,184 bytes "16 GB", so a
        // decimal split here would show a 16 GB Mac as having 17.18 GB.
        let used = splitBytes(memory.usedBytes, base: .binary)
        let total = splitBytes(memory.totalBytes, base: .binary, fractionDigits: 0)

        return .init(
            value: used.value,
            unit: used.unit,
            subtitle: String(
                format: NSLocalizedString("system_metric_memory_of_total", comment: "Memory card subtitle, e.g. 'of 16 GB'"),
                "\(total.value) \(total.unit)"
            ),
            fraction: memory.fraction,
            isIndeterminate: false
        )
    }

    private static func batteryContent(_ battery: BatterySummary) -> SystemMetricCardContent {
        guard battery.chargePercent > 0 || battery.isPluggedIn else {
            // A Mac mini or Studio has no battery at all.
            return noReading(
                subtitle: NSLocalizedString(
                    "system_metric_battery_none",
                    comment: "Battery card subtitle when the Mac has no battery"
                )
            )
        }

        return .init(
            value: decimalString(battery.chargePercent, fractionDigits: 0),
            unit: "%",
            subtitle: batterySubtitle(battery),
            fraction: battery.chargePercent / 100,
            isIndeterminate: false
        )
    }

    /// Health is the headline the card is here for, so it wins the subtitle
    /// when known; the time estimate is the fallback, and a Mac that has
    /// neither says so rather than showing a blank line.
    private static func batterySubtitle(_ battery: BatterySummary) -> String {
        if let health = battery.health {
            if health.isServiceRecommended {
                return NSLocalizedString("system_metric_battery_service", comment: "Battery card subtitle when Apple would recommend service")
            }
            return String(
                format: NSLocalizedString("system_metric_battery_health", comment: "Battery card subtitle showing maximum capacity, e.g. 'Health 92%'"),
                Int(health.maximumCapacityPercent.rounded())
            )
        }

        guard battery.minutesRemaining > 0 else {
            return battery.isCharging
                ? NSLocalizedString("system_metric_battery_charging", comment: "Battery card subtitle while charging with no time estimate")
                : NSLocalizedString("system_metric_battery_calculating", comment: "Battery card subtitle while macOS has no time estimate yet")
        }
        return durationString(minutes: battery.minutesRemaining)
    }

    private static func diskContent(_ disk: DiskUsage?) -> SystemMetricCardContent {
        guard let disk, disk.totalBytes > 0 else { return noReading() }
        // Decimal units here: storage is sold and reported by Apple in
        // decimal GB, so "105.12 GB free" matches Finder.
        let free = splitBytes(disk.availableBytes, base: .decimal)

        return .init(
            value: decimalString(disk.fraction * 100, fractionDigits: 0),
            unit: "%",
            subtitle: String(
                format: NSLocalizedString("system_metric_disk_free", comment: "Disk card subtitle, e.g. '105.12 GB free'"),
                "\(free.value) \(free.unit)"
            ),
            fraction: disk.fraction,
            isIndeterminate: false
        )
    }

    private static func networkContent(_ network: NetworkThroughput?) -> SystemMetricCardContent {
        guard let network else {
            return noReading(
                subtitle: NSLocalizedString(
                    "system_metric_network_measuring",
                    comment: "Network card subtitle before the first rate is available"
                )
            )
        }

        let down = splitRate(network.downloadBytesPerSecond)
        let up = splitRate(network.uploadBytesPerSecond)

        return .init(
            value: down.value,
            unit: down.unit,
            subtitle: String(
                format: NSLocalizedString("system_metric_network_upload", comment: "Network card subtitle showing upload rate, e.g. '↑ 240 KB/s'"),
                "\(up.value) \(up.unit)"
            ),
            fraction: min(1, network.downloadBytesPerSecond / networkRingFullScaleBytesPerSecond),
            isIndeterminate: false
        )
    }

    private static func wifiContent(_ wifi: WiFiSignal?) -> SystemMetricCardContent {
        guard let wifi else {
            return noReading(
                subtitle: NSLocalizedString(
                    "system_metric_wifi_unavailable",
                    comment: "Wi-Fi card subtitle when no signal reading is available"
                )
            )
        }

        return .init(
            value: "\(wifi.rssi)",
            unit: NSLocalizedString("system_metric_wifi_unit", comment: "Wi-Fi signal unit abbreviation: dBm"),
            // SSID needs Location Services on macOS 14+; without it CoreWLAN
            // returns nil and the card falls back to a quality word rather
            // than an empty line.
            subtitle: wifi.ssid ?? qualityDescription(wifi.quality),
            fraction: wifi.quality,
            isIndeterminate: false
        )
    }

    // MARK: - Shared formatting

    private static func coreSubtitle(_ coreCount: Int) -> String {
        String(
            format: NSLocalizedString("system_metric_cpu_cores", comment: "CPU card subtitle, e.g. '8 cores'"),
            coreCount
        )
    }

    static func qualityDescription(_ quality: Double) -> String {
        switch quality {
        case ..<0.3: return NSLocalizedString("system_metric_signal_weak", comment: "Signal quality: weak")
        case ..<0.65: return NSLocalizedString("system_metric_signal_fair", comment: "Signal quality: fair")
        default: return NSLocalizedString("system_metric_signal_strong", comment: "Signal quality: strong")
        }
    }

    /// "41m", "1h 20m". Hours are dropped below an hour so the common case
    /// stays short enough for a card subtitle.
    static func durationString(minutes: Int) -> String {
        let clamped = max(0, minutes)
        let hours = clamped / 60
        let remainder = clamped % 60
        if hours == 0 {
            return String(format: NSLocalizedString("duration_minutes", comment: "A duration under an hour, e.g. '41m'"), remainder)
        }
        if remainder == 0 {
            return String(format: NSLocalizedString("duration_hours", comment: "A whole number of hours, e.g. '2h'"), hours)
        }
        return String(format: NSLocalizedString("duration_hours_minutes", comment: "A duration of hours and minutes, e.g. '1h 20m'"), hours, remainder)
    }

    enum ByteBase {
        /// 1024-based, labelled GB — how macOS reports memory.
        case binary
        /// 1000-based — how macOS (and every drive manufacturer) reports storage.
        case decimal

        var step: Double { self == .binary ? 1024 : 1000 }
    }

    private static let byteUnits = ["B", "KB", "MB", "GB", "TB", "PB"]

    /// Splits a byte count into a localized number and its unit, so the two
    /// can be typeset at different sizes.
    ///
    /// `fractionDigits` defaults to "2 below 100, 0 at or above", which keeps
    /// "12.43 GB" precise and "512 GB" from reading as "512.00 GB".
    static func splitBytes(_ bytes: UInt64, base: ByteBase, fractionDigits: Int? = nil) -> (value: String, unit: String) {
        var value = Double(bytes)
        var index = 0
        while value >= base.step && index < byteUnits.count - 1 {
            value /= base.step
            index += 1
        }
        let digits = fractionDigits ?? (value >= 100 ? 0 : 2)
        return (decimalString(value, fractionDigits: digits), byteUnits[index])
    }

    /// Splits a byte *rate* into a number and a "…/s" unit.
    ///
    /// Rates use decimal steps (network equipment is specified that way) and
    /// at most one decimal — a second decimal on a number that changes every
    /// two seconds is noise.
    static func splitRate(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        var value = max(0, bytesPerSecond)
        var index = 0
        while value >= 1000 && index < byteUnits.count - 1 {
            value /= 1000
            index += 1
        }
        let digits = index == 0 || value >= 100 ? 0 : 1
        return (
            decimalString(value, fractionDigits: digits),
            String(format: NSLocalizedString("%@/s", comment: "Data rate, e.g. '1.2 MB/s'"), byteUnits[index])
        )
    }

    /// Locale-aware: a German user sees "12,43", matching the rest of the OS.
    static func decimalString(_ value: Double, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value.rounded()))"
    }
}
