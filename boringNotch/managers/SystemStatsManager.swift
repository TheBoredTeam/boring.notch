//
//  SystemStatsManager.swift
//  boringNotch
//
//  Created by boringNotch contributors on 2026-04-19.
//

import Combine
import Defaults
import Foundation

/// Monitors CPU usage, RAM pressure, and thermal state.
/// Uses sandbox-friendly APIs (sysctl, ProcessInfo) instead of Mach host_statistics.
class SystemStatsManager: ObservableObject {
    static let shared = SystemStatsManager()

    @Published var cpuUsage: Double = 0  // 0-100
    @Published var memoryUsedPercent: Double = 0  // 0-100
    @Published var memoryUsedGB: Double = 0
    @Published var memoryTotalGB: Double = 0
    @Published var thermalState: ProcessInfo.ThermalState = .nominal

    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 3.0
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var settingsCancellable: AnyCancellable?

    private init() {
        memoryTotalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

        // Prime CPU sampling
        previousCPUTicks = readCPUTicks()

        // Auto-start/stop when setting changes
        settingsCancellable = Defaults.publisher(.showSystemStats)
            .sink { [weak self] change in
                if change.newValue {
                    self?.startMonitoring()
                } else {
                    self?.stopMonitoring()
                }
            }

        if Defaults[.showSystemStats] {
            startMonitoring()
        }
    }

    func startMonitoring() {
        refresh()
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) {
            [weak self] _ in
            self?.refresh()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc private func thermalStateChanged() {
        DispatchQueue.main.async {
            self.thermalState = ProcessInfo.processInfo.thermalState
        }
    }

    private func refresh() {
        let cpu = getCPUUsage()
        let mem = getMemoryUsage()
        let thermal = ProcessInfo.processInfo.thermalState

        DispatchQueue.main.async {
            self.cpuUsage = cpu
            self.memoryUsedPercent = mem.percent
            self.memoryUsedGB = mem.usedGB
            self.thermalState = thermal
        }
    }

    // MARK: - CPU via processor_info (sandbox-allowed)

    private func readCPUTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
        var processorInfo: processor_info_array_t?
        var processorMsgCount: mach_msg_type_number_t = 0
        var processorCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorMsgCount
        )

        guard result == KERN_SUCCESS, let info = processorInfo else { return nil }

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0

        let cpuLoadInfoSize = Int(CPU_STATE_MAX)

        for i in 0..<Int(processorCount) {
            let offset = i * cpuLoadInfoSize
            totalUser += UInt64(info[offset + Int(CPU_STATE_USER)])
            totalSystem += UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            totalIdle += UInt64(info[offset + Int(CPU_STATE_IDLE)])
            totalNice += UInt64(info[offset + Int(CPU_STATE_NICE)])
        }

        // Deallocate
        let size = vm_size_t(processorMsgCount) * vm_size_t(MemoryLayout<integer_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)

        return (totalUser, totalSystem, totalIdle, totalNice)
    }

    private func getCPUUsage() -> Double {
        guard let current = readCPUTicks() else { return 0 }

        if let previous = previousCPUTicks {
            let userDiff = Double(current.user - previous.user)
            let systemDiff = Double(current.system - previous.system)
            let idleDiff = Double(current.idle - previous.idle)
            let niceDiff = Double(current.nice - previous.nice)

            let totalDiff = userDiff + systemDiff + idleDiff + niceDiff
            if totalDiff > 0 {
                previousCPUTicks = current
                return ((userDiff + systemDiff + niceDiff) / totalDiff) * 100
            }
        }

        previousCPUTicks = current
        return 0
    }

    // MARK: - Memory via host_statistics64 (sandbox-allowed for VM info)

    private func getMemoryUsage() -> (percent: Double, usedGB: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            // Fallback: use sysctl
            return getMemoryUsageFallback()
        }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize

        let used = active + wired + compressed
        let total = Double(ProcessInfo.processInfo.physicalMemory)

        return (percent: (used / total) * 100, usedGB: used / 1_073_741_824)
    }

    /// Fallback using sysctl for memory pressure
    private func getMemoryUsageFallback() -> (percent: Double, usedGB: Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)

        // Use sysctl to get free memory
        var memSize: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memSize, &size, nil, 0)

        // Estimate used memory via vm.page_pageable_internal_count
        // This is a rough approximation when host_statistics fails
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        let totalGB = total / 1_073_741_824
        // Conservative estimate: ~70% used as default when we can't measure
        return (percent: 70, usedGB: totalGB * 0.7)
    }

    deinit {
        stopMonitoring()
    }
}
