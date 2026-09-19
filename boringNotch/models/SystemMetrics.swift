//
//  SystemMetrics.swift
//  boringNotch
//
//  Value types for the system monitor, plus the arithmetic that turns raw
//  kernel counters into the numbers shown in the notch.
//
//  Everything here is deliberately free of system calls: sampling lives in
//  `SystemMonitorManager`, and this file only transforms values it is handed.
//  That split is what makes the interesting parts — counter deltas, wrap
//  handling, byte/percent formatting — testable without a running Mac in a
//  particular state.
//

import Foundation

// MARK: - CPU

/// A single reading of the kernel's cumulative per-state CPU tick counters.
///
/// Absolute values are meaningless on their own; usage is the *delta* between
/// two samples, which is why this type only ever appears in pairs.
struct CPUTicks: Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    static let zero = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)

    var busy: UInt64 { user &+ system &+ nice }
    var total: UInt64 { busy &+ idle }
}

struct CPUUsage: Equatable {
    /// Fraction of wall-clock time the CPU spent doing work, 0...1.
    var load: Double
    /// User + nice share of that work, 0...1. Split out so the gauge can show
    /// user vs. system the way Activity Monitor does.
    var userLoad: Double
    var systemLoad: Double

    /// Usage over the interval between two tick readings.
    ///
    /// Returns nil when the pair carries no information: an empty interval
    /// (two samples within the same tick) or counters that moved backwards.
    /// The counters are 32-bit per-CPU values summed into 64-bit here, so a
    /// backwards step means a core came online/offline between samples — the
    /// delta is meaningless and a *wrong* number is worse than "no reading yet".
    static func between(previous: CPUTicks, current: CPUTicks) -> CPUUsage? {
        guard current.user >= previous.user,
              current.system >= previous.system,
              current.idle >= previous.idle,
              current.nice >= previous.nice
        else { return nil }

        let user = Double(current.user - previous.user)
        let system = Double(current.system - previous.system)
        let nice = Double(current.nice - previous.nice)
        let idle = Double(current.idle - previous.idle)

        let total = user + system + nice + idle
        guard total > 0 else { return nil }

        return CPUUsage(
            load: (user + system + nice) / total,
            userLoad: (user + nice) / total,
            systemLoad: system / total
        )
    }
}

// MARK: - Memory

/// How hard the VM subsystem is working, as reported by
/// `kern.memorystatus_vm_pressure_level`.
enum MemoryPressureLevel: Int, Equatable, CaseIterable {
    case normal = 1
    case warning = 2
    case critical = 4

    /// The sysctl is documented to return 1/2/4; anything else is treated as
    /// normal rather than crashing or inventing a fourth state.
    init(rawSysctlValue: Int32) {
        self = MemoryPressureLevel(rawValue: Int(rawSysctlValue)) ?? .normal
    }

    var localizedDescription: String {
        switch self {
        case .normal:
            return NSLocalizedString("memory_pressure_normal", comment: "Memory pressure level: normal")
        case .warning:
            return NSLocalizedString("memory_pressure_warning", comment: "Memory pressure level: warning")
        case .critical:
            return NSLocalizedString("memory_pressure_critical", comment: "Memory pressure level: critical")
        }
    }
}

/// Page counts straight out of `host_statistics64(HOST_VM_INFO64)`, before
/// they are scaled by the page size.
struct MemoryPageCounts: Equatable {
    var active: UInt64
    var inactive: UInt64
    var wired: UInt64
    var compressed: UInt64
    var purgeable: UInt64
    var speculative: UInt64
    var free: UInt64
}

struct MemoryUsage: Equatable {
    var usedBytes: UInt64
    var totalBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var appBytes: UInt64
    var pressure: MemoryPressureLevel

    /// Fraction of physical memory in use, 0...1.
    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(usedBytes) / Double(totalBytes))
    }

    /// Mirrors Activity Monitor's "Memory Used": app memory (anonymous pages
    /// that aren't purgeable) + wired + compressed. Cached/inactive file
    /// pages are excluded — the kernel reclaims those on demand, so counting
    /// them would show every idle Mac pinned near 100%.
    init(pages: MemoryPageCounts, pageSize: UInt64, totalBytes: UInt64, pressure: MemoryPressureLevel) {
        // active includes purgeable pages; subtracting with saturation keeps a
        // racy sample (purgeable read a moment after active) from underflowing.
        let appPages = pages.active > pages.purgeable ? pages.active - pages.purgeable : 0
        let usedPages = appPages + pages.wired + pages.compressed

        self.appBytes = appPages * pageSize
        self.wiredBytes = pages.wired * pageSize
        self.compressedBytes = pages.compressed * pageSize
        // Clamp: the page counts and the total come from different sources and
        // a sample straddling a memory-state change can otherwise exceed 100%.
        self.usedBytes = min(usedPages * pageSize, totalBytes)
        self.totalBytes = totalBytes
        self.pressure = pressure
    }

    init(usedBytes: UInt64, totalBytes: UInt64, wiredBytes: UInt64, compressedBytes: UInt64, appBytes: UInt64, pressure: MemoryPressureLevel) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.appBytes = appBytes
        self.pressure = pressure
    }
}

// MARK: - Network

/// Cumulative interface byte counters at a point in time.
struct NetworkByteCounts: Equatable {
    var received: UInt64
    var sent: UInt64

    static let zero = NetworkByteCounts(received: 0, sent: 0)
}

struct NetworkThroughput: Equatable {
    var downloadBytesPerSecond: Double
    var uploadBytesPerSecond: Double

    static let zero = NetworkThroughput(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)

    /// Throughput between two counter readings.
    ///
    /// Counters reset when an interface goes down or the set of interfaces
    /// changes (Wi-Fi off, VPN up, dock unplugged), which shows up as the
    /// total moving backwards. Reporting a huge negative-turned-positive
    /// spike there would be worse than reporting nothing, so a backwards step
    /// yields zero for that direction and the next interval recovers.
    static func between(previous: NetworkByteCounts, current: NetworkByteCounts, interval: TimeInterval) -> NetworkThroughput {
        guard interval > 0 else { return .zero }

        let down = current.received >= previous.received ? current.received - previous.received : 0
        let up = current.sent >= previous.sent ? current.sent - previous.sent : 0

        return NetworkThroughput(
            downloadBytesPerSecond: Double(down) / interval,
            uploadBytesPerSecond: Double(up) / interval
        )
    }
}

// MARK: - Disk

struct DiskUsage: Equatable {
    var usedBytes: UInt64
    var totalBytes: UInt64

    var availableBytes: UInt64 { totalBytes > usedBytes ? totalBytes - usedBytes : 0 }

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(usedBytes) / Double(totalBytes))
    }
}

// MARK: - Wi-Fi

struct WiFiSignal: Equatable {
    /// Received signal strength in dBm. Typically -30 (excellent) to -90 (unusable).
    var rssi: Int
    var ssid: String?

    /// Signal strength mapped to 0...1 across the usable dBm range.
    ///
    /// -50 dBm and better reads as full, -90 and worse as empty. Below-range
    /// values are clamped rather than extrapolated: a bar can't be more than
    /// full, and dBm scales are not linear in perceived quality anyway.
    var quality: Double {
        let best = -50.0
        let worst = -90.0
        let clamped = min(best, max(worst, Double(rssi)))
        return (clamped - worst) / (best - worst)
    }

    /// Coarse bucket for icon selection — matches how macOS draws its own
    /// Wi-Fi glyph (roughly quarter bars).
    var bars: Int {
        switch quality {
        case ..<0.15: return 0
        case ..<0.4: return 1
        case ..<0.7: return 2
        default: return 3
        }
    }
}

// MARK: - Battery health

struct BatteryHealth: Equatable {
    /// Maximum capacity as a percentage of design capacity, 0...100.
    var maximumCapacityPercent: Double

    /// Apple replaces a battery under "Service Recommended", which it starts
    /// showing around 80% of design capacity.
    var isServiceRecommended: Bool { maximumCapacityPercent < 80 }
}

// MARK: - Snapshot

/// Everything the monitor knows at one instant.
///
/// Every field is optional and nil means "no reading": not available on this
/// Mac, not permitted, or — for the rate-based metrics — not yet, because CPU
/// and network both need two samples before they mean anything. Modelling
/// that as `nil` rather than as a zero value is what stops the first tick of
/// the monitor from confidently reporting an idle machine.
struct SystemMetricsSnapshot: Equatable {
    var cpu: CPUUsage?
    var memory: MemoryUsage?
    var disk: DiskUsage?
    var network: NetworkThroughput?
    var wifi: WiFiSignal?
    var batteryHealth: BatteryHealth?
}

// MARK: - Formatting

/// Shared formatting so the header gauges, the expanded panel and any future
/// surface all render a given metric identically.
enum SystemMetricFormatter {
    /// "42%" — no decimals. At a glance in a notch, tenths are noise.
    static func percent(_ fraction: Double) -> String {
        let clamped = min(1, max(0, fraction))
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// Byte counts in the units Finder uses (decimal GB, not GiB), so "228 GB
    /// free" matches what the user sees in About This Mac.
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(clamping: value))
    }

    /// "1.2 MB/s". Rates are per-second by definition, so the unit is baked in
    /// rather than left to the caller to append inconsistently.
    static func bytesPerSecond(_ value: Double) -> String {
        let clamped = max(0, value)
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        formatter.zeroPadsFractionDigits = false
        let amount = formatter.string(fromByteCount: Int64(clamping: UInt64(clamped.rounded())))
        return String(format: NSLocalizedString("%@/s", comment: "Data rate, e.g. '1.2 MB/s'"), amount)
    }

    /// dBm is the honest unit for signal strength and what every other Mac
    /// network tool shows, so it is displayed rather than hidden behind bars.
    static func rssi(_ value: Int) -> String {
        String(format: NSLocalizedString("%d dBm", comment: "Wi-Fi signal strength in dBm"), value)
    }

    /// Placeholder for a metric that isn't available — an em dash, not "0",
    /// so "unknown" never reads as "nothing is happening".
    static let unavailable = "—"
}
