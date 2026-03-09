//
//  SystemMonitorManager.swift
//  boringNotch
//
//  Created by Zaky Syihab Hatmoko on 05/03/2026.
//

import Combine
import Defaults
import Foundation

/// Manages polling of system CPU and memory usage statistics.
/// Uses Mach kernel APIs for accurate, low-overhead measurements.
class SystemMonitorManager: ObservableObject {

    static let shared = SystemMonitorManager()

    // MARK: - Published Properties

    /// Current CPU usage as a percentage (0-100)
    @Published private(set) var cpuUsage: Double = 0.0

    /// Current memory used in GB
    @Published private(set) var memoryUsed: Double = 0.0

    /// Total physical memory in GB
    let memoryTotal: Double

    /// Memory usage as a percentage (0-100)
    var memoryUsagePercent: Double {
        guard memoryTotal > 0 else { return 0 }
        return (memoryUsed / memoryTotal) * 100.0
    }

    // MARK: - Private Properties

    private var timer: Timer?
    private var defaultsObservation: Defaults.Observation?

    /// Previous CPU tick counts for delta calculation
    private var previousCPUInfo: host_cpu_load_info?

    /// Cached Mach host port to avoid leaking send rights on every poll.
    private let hostPort: mach_port_t

    private let pollingInterval: TimeInterval = 3.0

    // MARK: - Init

    private init() {
        self.hostPort = mach_host_self()
        self.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)

        // Take an initial CPU snapshot so the first real reading has a baseline
        previousCPUInfo = fetchCPULoadInfo()

        // Observe the setting toggle to start/stop polling
        defaultsObservation = Defaults.observe(.showSystemMonitor) { [weak self] change in
            DispatchQueue.main.async {
                if change.newValue {
                    self?.startPolling()
                } else {
                    self?.stopPolling()
                }
            }
        }

        // Start polling immediately if the setting is already on
        if Defaults[.showSystemMonitor] {
            startPolling()
        }
    }

    // MARK: - Polling

    private func startPolling() {
        guard timer == nil else { return }

        // Perform an initial update immediately
        updateStats()

        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func updateStats() {
        let cpu = measureCPUUsage()
        let mem = measureMemoryUsed()

        DispatchQueue.main.async { [weak self] in
            self?.cpuUsage = cpu
            self?.memoryUsed = mem
        }
    }

    // MARK: - CPU Measurement

    /// Fetches the current aggregate CPU load info from the kernel.
    private func fetchCPULoadInfo() -> host_cpu_load_info? {
        var size = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )
        let hostInfo = host_cpu_load_info_t.allocate(capacity: 1)
        defer { hostInfo.deallocate() }

        let result = hostInfo.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { ptr in
            host_statistics(hostPort, HOST_CPU_LOAD_INFO, ptr, &size)
        }

        guard result == KERN_SUCCESS else { return nil }
        return hostInfo.pointee
    }

    /// Calculates CPU usage percentage based on tick delta since last poll.
    private func measureCPUUsage() -> Double {
        guard let current = fetchCPULoadInfo() else { return cpuUsage }

        defer { previousCPUInfo = current }

        guard let previous = previousCPUInfo else { return 0 }

        let userDelta = Double(current.cpu_ticks.0 - previous.cpu_ticks.0)   // CPU_STATE_USER
        let systemDelta = Double(current.cpu_ticks.1 - previous.cpu_ticks.1) // CPU_STATE_SYSTEM
        let idleDelta = Double(current.cpu_ticks.2 - previous.cpu_ticks.2)   // CPU_STATE_IDLE
        let niceDelta = Double(current.cpu_ticks.3 - previous.cpu_ticks.3)   // CPU_STATE_NICE

        let totalTicks = userDelta + systemDelta + idleDelta + niceDelta
        guard totalTicks > 0 else { return 0 }

        let usedTicks = userDelta + systemDelta + niceDelta
        return (usedTicks / totalTicks) * 100.0
    }

    // MARK: - Memory Measurement

    /// Measures current memory usage using Mach VM statistics.
    /// Returns memory used in GB (active + wired + compressed).
    private func measureMemoryUsed() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return memoryUsed }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize

        let usedBytes = active + wired + compressed
        return usedBytes / (1024 * 1024 * 1024)
    }

    // MARK: - Cleanup

    deinit {
        stopPolling()
        defaultsObservation?.invalidate()
        mach_port_deallocate(mach_task_self_, hostPort)
    }
}
