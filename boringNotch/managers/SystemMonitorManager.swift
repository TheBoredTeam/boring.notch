//
//  SystemMonitorManager.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-09.
//
//  Lightweight CPU / memory / network sampler for the system-monitor widget.
//  Sampling only runs while a view has called `start()`.
//

import Combine
import Darwin
import Defaults
import Foundation

final class SystemMonitorManager: ObservableObject {
    static let shared = SystemMonitorManager()

    @Published private(set) var cpuUsage: Double = 0          // 0...1
    @Published private(set) var memoryUsage: Double = 0       // 0...1
    @Published private(set) var memoryUsedGB: Double = 0
    @Published private(set) var memoryTotalGB: Double = 0
    @Published private(set) var networkDownBytesPerSec: Double = 0
    @Published private(set) var networkUpBytesPerSec: Double = 0
    @Published private(set) var diskUsage: Double = 0         // 0...1
    @Published private(set) var diskUsedGB: Double = 0
    @Published private(set) var diskTotalGB: Double = 0
    @Published private(set) var cpuTemperature: Double?       // °C, nil if unavailable

    private var timer: Timer?
    private var subscriberCount = 0
    private var previousCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var previousNet: (down: UInt64, up: UInt64, time: Date)?
    private lazy var temperatureReader = CPUTemperatureReader()

    private init() {}

    /// Begins sampling. Reference-counted so multiple views can share the timer.
    func start() {
        subscriberCount += 1
        guard timer == nil else { return }
        sample()
        let interval = max(0.5, Defaults[.monitorRefreshRate])
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    /// Stops sampling once the last subscriber goes away.
    func stop() {
        subscriberCount = max(0, subscriberCount - 1)
        if subscriberCount == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    private func sample() {
        let cpu = readCPUUsage()
        let mem = readMemory()
        let net = readNetwork()
        let disk = readDisk()
        // CPU temperature via in-process IOHID (works because the app is not sandboxed).
        let wantTemp = Defaults[.showTemperatureMonitor] || Defaults[.homeShowCPUTemp]
        let temp = wantTemp ? temperatureReader?.readAverage() : nil
        DispatchQueue.main.async {
            if let cpu { self.cpuUsage = cpu }
            self.memoryUsage = mem.usage
            self.memoryUsedGB = mem.usedGB
            self.memoryTotalGB = mem.totalGB
            self.networkDownBytesPerSec = net.down
            self.networkUpBytesPerSec = net.up
            self.diskUsage = disk.usage
            self.diskUsedGB = disk.usedGB
            self.diskTotalGB = disk.totalGB
            if wantTemp { self.cpuTemperature = temp }
        }
    }

    // MARK: - Disk

    private func readDisk() -> (usage: Double, usedGB: Double, totalGB: Double) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage
        else { return (0, 0, 0) }

        let totalBytes = Double(total)
        let usedBytes = max(0, totalBytes - Double(available))
        let usage = totalBytes > 0 ? usedBytes / totalBytes : 0
        // Finder uses decimal GB (1e9).
        return (min(1, max(0, usage)), usedBytes / 1_000_000_000, totalBytes / 1_000_000_000)
    }

    // MARK: - CPU

    private func readCPUUsage() -> Double? {
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        var cpuLoad = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let user = cpuLoad.cpu_ticks.0
        let system = cpuLoad.cpu_ticks.1
        let idle = cpuLoad.cpu_ticks.2
        let nice = cpuLoad.cpu_ticks.3
        defer { previousCPUTicks = (user, system, idle, nice) }

        guard let prev = previousCPUTicks else { return nil }
        let userDiff = Double(user &- prev.user)
        let systemDiff = Double(system &- prev.system)
        let idleDiff = Double(idle &- prev.idle)
        let niceDiff = Double(nice &- prev.nice)
        let total = userDiff + systemDiff + idleDiff + niceDiff
        guard total > 0 else { return nil }
        return min(1, max(0, (userDiff + systemDiff + niceDiff) / total))
    }

    // MARK: - Memory

    private func readMemory() -> (usage: Double, usedGB: Double, totalGB: Double) {
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        let totalGB = totalBytes / 1_073_741_824

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0, totalGB) }

        let pageSize = Double(vm_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let usage = totalBytes > 0 ? used / totalBytes : 0
        return (min(1, max(0, usage)), used / 1_073_741_824, totalGB)
    }

    // MARK: - Network

    private func readNetwork() -> (down: Double, up: Double) {
        var down: UInt64 = 0
        var up: UInt64 = 0

        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr = ifaddrPtr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP,
                let addr = cur.pointee.ifa_addr,
                addr.pointee.sa_family == UInt8(AF_LINK),
                let data = cur.pointee.ifa_data
            else { continue }

            let name = String(cString: cur.pointee.ifa_name)
            if name.hasPrefix("lo") { continue }

            let networkData = data.assumingMemoryBound(to: if_data.self)
            down += UInt64(networkData.pointee.ifi_ibytes)
            up += UInt64(networkData.pointee.ifi_obytes)
        }

        let now = Date()
        defer { previousNet = (down, up, now) }
        guard let prev = previousNet else { return (0, 0) }
        let dt = now.timeIntervalSince(prev.time)
        guard dt > 0 else { return (0, 0) }

        // Underlying counters are 32-bit and may reset; clamp negatives to 0.
        let downDiff = down >= prev.down ? Double(down - prev.down) : 0
        let upDiff = up >= prev.up ? Double(up - prev.up) : 0
        return (downDiff / dt, upDiff / dt)
    }
}

extension SystemMonitorManager {
    /// Human-readable bytes/sec, e.g. "1.2 MB/s".
    static func formatRate(_ bytesPerSec: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bytesPerSec
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return String(format: value >= 100 || unit == 0 ? "%.0f %@" : "%.1f %@", value, units[unit])
    }
}
