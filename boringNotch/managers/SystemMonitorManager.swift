//
//  SystemMonitorManager.swift
//  boringNotch
//
//  Samples the system counters behind the notch's system monitor.
//
//  Two design constraints drive the shape of this file:
//
//  1. Sampling is *refcounted*. A notch app polling the kernel every couple
//     of seconds forever is exactly the kind of thing that shows up as
//     battery drain, so the timer only runs while a view is actually on
//     screen asking for numbers. No subscribers, no timer, no work.
//  2. The arithmetic lives in `SystemMetrics.swift`. This file's job is to
//     read counters and hand them over; anything with a branch in it that
//     could be wrong belongs somewhere a test can reach.
//

import Combine
import CoreWLAN
import Darwin
import Defaults
import Foundation
import SwiftUI

@MainActor
final class SystemMonitorManager: ObservableObject {
    static let shared = SystemMonitorManager()

    /// The most recent reading. Starts out as `.unknown`/zero, so views must
    /// be able to render "no data yet" — they will see it for one interval
    /// after the first subscriber appears.
    @Published private(set) var snapshot = SystemMetricsSnapshot()

    private var subscriberCount = 0
    private var samplingTask: Task<Void, Never>?

    private var previousCPUTicks: CPUTicks?
    /// Network counters are stored *with* the moment they were read, not
    /// against a shared "last sample" timestamp. The two drift apart as soon
    /// as the network card is switched off: the shared timestamp keeps
    /// advancing while the counters go stale, and re-enabling the card would
    /// then divide minutes of accumulated traffic by one interval.
    private var previousNetworkSample: (counts: NetworkByteCounts, date: Date)?

    private var enabledCancellable: AnyCancellable?

    private init() {
        // Turning the feature off should stop the polling immediately rather
        // than at the next view teardown.
        enabledCancellable = Defaults.publisher(.systemMonitorEnabled)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self else { return }
                    if change.newValue {
                        self.startIfNeeded()
                    } else {
                        self.stop()
                    }
                }
            }
    }

    // MARK: - Subscription

    /// Call from `.onAppear` of any view that displays metrics; balance it
    /// with `endObserving()` in `.onDisappear`.
    func beginObserving() {
        subscriberCount += 1
        startIfNeeded()
    }

    func endObserving() {
        subscriberCount = max(0, subscriberCount - 1)
        if subscriberCount == 0 {
            stop()
        }
    }

    private func startIfNeeded() {
        guard samplingTask == nil, subscriberCount > 0, Defaults[.systemMonitorEnabled] else { return }

        // Reset the deltas: counters kept from a previous run would be
        // differenced against a much later reading and report a nonsense
        // average over the gap.
        previousCPUTicks = nil
        previousNetworkSample = nil
        snapshot = SystemMetricsSnapshot()

        // Created from a @MainActor method, so the closure inherits that
        // isolation — the counter reads inside `sample()` are the part that
        // hops off, not the loop.
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.sample()
                try? await Task.sleep(for: .seconds(max(0.5, Defaults[.systemMonitorRefreshInterval])))
            }
        }
    }

    private func stop() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    // MARK: - Sampling

    private func sample() async {
        let enabled = Defaults[.systemMonitorMetrics]

        // The reads themselves are cheap syscalls, but they are not free and
        // there is no reason to do them on the main actor.
        let reading = await Task.detached(priority: .utility) {
            SystemCounters.read(metrics: enabled)
        }.value
        let now = Date()

        var next = snapshot

        if let ticks = reading.cpuTicks {
            if let previous = previousCPUTicks {
                // A rejected pair (a core came online mid-interval, see
                // CPUUsage.between) keeps the last good figure for one tick
                // rather than blinking to a dash — the reading is one interval
                // stale, which is far less distracting than a flicker.
                next.cpu = CPUUsage.between(previous: previous, current: ticks) ?? next.cpu
            }
            previousCPUTicks = ticks
        } else {
            // The card was switched off. Dropping the baseline means the next
            // reading after it comes back is measured over one interval rather
            // than reported as an average of the whole gap.
            previousCPUTicks = nil
            next.cpu = nil
        }

        next.memory = reading.memory
        next.disk = reading.disk

        if let counts = reading.networkCounts {
            if let previous = previousNetworkSample {
                let interval = now.timeIntervalSince(previous.date)
                if interval > 0 {
                    next.network = NetworkThroughput.between(
                        previous: previous.counts, current: counts, interval: interval
                    )
                }
            }
            previousNetworkSample = (counts, now)
        } else {
            previousNetworkSample = nil
            next.network = nil
        }

        // Wi-Fi and battery health are read every tick but are allowed to be
        // nil — an Ethernet-only Mac or a desktop has neither, and the views
        // show a dash rather than a fabricated zero.
        next.wifi = enabled.contains(.wifi) ? reading.wifi : nil
        next.batteryHealth = enabled.contains(.battery) ? batteryHealth() : nil

        snapshot = next
    }

    /// Battery health comes from the existing battery view model rather than a
    /// second IOKit subscription — it already tracks max capacity and is
    /// updated by the system's own power-source notifications.
    private func batteryHealth() -> BatteryHealth? {
        guard let capacity = BatteryStatusViewModel.shared.maxCapacity, capacity > 0 else { return nil }
        return BatteryHealth(maximumCapacityPercent: Double(capacity))
    }
}

// MARK: - Raw counter reads

/// The kernel-facing half. Free functions in an enum so they can run off the
/// main actor without dragging the observable object along.
enum SystemCounters {
    struct Reading {
        var cpuTicks: CPUTicks?
        var memory: MemoryUsage?
        var disk: DiskUsage?
        var networkCounts: NetworkByteCounts?
        var wifi: WiFiSignal?
    }

    /// Reads only what is switched on. Each metric is independent, so a Mac
    /// where one read fails (no Wi-Fi hardware, a volume that won't report
    /// capacity) still gets the rest.
    static func read(metrics: Set<SystemMetricKind>) -> Reading {
        Reading(
            cpuTicks: metrics.contains(.cpu) ? cpuTicks() : nil,
            memory: metrics.contains(.memory) ? memoryUsage() : nil,
            disk: metrics.contains(.disk) ? diskUsage() : nil,
            networkCounts: metrics.contains(.network) ? networkCounts() : nil,
            wifi: metrics.contains(.wifi) ? wifiSignal() : nil
        )
    }

    // MARK: CPU

    static func cpuTicks() -> CPUTicks? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: UnsafeRawPointer(info))),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        var ticks = CPUTicks.zero
        let states = Int(CPU_STATE_MAX)
        for core in 0..<Int(cpuCount) {
            let base = core * states
            // The counters are unsigned but typed as `integer_t` (Int32), so
            // they read as negative once they pass 2^31. Reinterpreting the
            // bit pattern is what keeps a long-uptime Mac from reporting
            // garbage.
            func tick(_ state: Int32) -> UInt64 {
                UInt64(UInt32(bitPattern: info[base + Int(state)]))
            }
            ticks.user &+= tick(CPU_STATE_USER)
            ticks.system &+= tick(CPU_STATE_SYSTEM)
            ticks.idle &+= tick(CPU_STATE_IDLE)
            ticks.nice &+= tick(CPU_STATE_NICE)
        }
        return ticks
    }

    // MARK: Memory

    static func memoryUsage() -> MemoryUsage? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }

        let pages = MemoryPageCounts(
            active: UInt64(stats.active_count),
            inactive: UInt64(stats.inactive_count),
            wired: UInt64(stats.wire_count),
            compressed: UInt64(stats.compressor_page_count),
            purgeable: UInt64(stats.purgeable_count),
            speculative: UInt64(stats.speculative_count),
            free: UInt64(stats.free_count)
        )

        return MemoryUsage(
            pages: pages,
            pageSize: UInt64(pageSize),
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            pressure: memoryPressureLevel()
        )
    }

    static func memoryPressureLevel() -> MemoryPressureLevel {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        return MemoryPressureLevel(rawSysctlValue: level)
    }

    // MARK: Disk

    static func diskUsage() -> DiskUsage? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else { return nil }

        guard let total = values.volumeTotalCapacity, total > 0 else { return nil }

        // `...ForImportantUsage` is the number Finder and Settings show: it
        // counts space that can be reclaimed from purgeable caches, so it
        // matches the user's mental model of "free space" better than the raw
        // available count does.
        let available = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) } ?? 0
        let totalBytes = UInt64(total)
        return DiskUsage(usedBytes: totalBytes > available ? totalBytes - available : 0, totalBytes: totalBytes)
    }

    // MARK: Network

    /// Interfaces excluded from the totals.
    ///
    /// `lo` is loopback. `awdl`/`llw` carry AirDrop and friends, which is not
    /// what "network speed" means to anyone. `utun`/`ipsec`/`ppp` are tunnels:
    /// their bytes also traverse the physical interface underneath, so
    /// counting both double-reports every byte of VPN traffic.
    private static let excludedInterfacePrefixes = ["lo", "awdl", "llw", "utun", "ipsec", "ppp", "gif", "stf"]

    static func networkCounts() -> NetworkByteCounts? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var counts = NetworkByteCounts.zero
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            // Byte counters live on the link-layer entry for each interface;
            // the AF_INET/AF_INET6 entries for the same interface carry
            // addresses, not statistics.
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.ifa_data
            else { continue }

            let name = String(cString: interface.ifa_name)
            guard !excludedInterfacePrefixes.contains(where: { name.hasPrefix($0) }) else { continue }

            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            counts.received &+= UInt64(stats.ifi_ibytes)
            counts.sent &+= UInt64(stats.ifi_obytes)
        }
        return counts
    }

    // MARK: Wi-Fi

    static func wifiSignal() -> WiFiSignal? {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else { return nil }

        let rssi = interface.rssiValue()
        // CoreWLAN reports 0 both for "no association" and for "you aren't
        // allowed to know" — macOS 14+ gates signal strength behind Location
        // Services. Either way there is no number to show.
        guard rssi != 0 else { return nil }

        return WiFiSignal(rssi: rssi, ssid: interface.ssid())
    }
}
