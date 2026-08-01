//
//  SystemActivityMonitor.swift
//  boringNotch
//

import Foundation

struct SystemActivitySample: Sendable {
    var cpuUsagePercent: Double?
    var gpuUsagePercent: Double?
    var memoryUsedBytes: UInt64
    var memoryTotalBytes: UInt64
    var cpuTemperatureCelsius: Double?
    var thermalState: Int

    static let empty = SystemActivitySample(
        cpuUsagePercent: nil,
        gpuUsagePercent: nil,
        memoryUsedBytes: 0,
        memoryTotalBytes: 0,
        cpuTemperatureCelsius: nil,
        thermalState: -1
    )

    var memoryUsagePercent: Double? {
        guard memoryTotalBytes > 0 else { return nil }
        return Double(memoryUsedBytes) / Double(memoryTotalBytes) * 100
    }

    var thermalStateLabel: String {
        switch thermalState {
        case 0: "Nominal"
        case 1: "Fair"
        case 2: "Serious"
        case 3: "Critical"
        default: "Thermal state"
        }
    }
}

private struct CPUTickSnapshot: Sendable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
}

@MainActor
final class SystemActivityMonitor: ObservableObject {
    static let shared = SystemActivityMonitor()

    @Published private(set) var sample = SystemActivitySample.empty
    @Published private(set) var isLoading = false

    private var selection: BNSystemMetricSelection = []
    private var previousCPUTicks: CPUTickSnapshot?
    private var refreshTask: Task<Void, Never>?

    private init() {}

    func start(requesting newSelection: BNSystemMetricSelection) {
        guard !newSelection.isEmpty else {
            stop()
            return
        }
        guard refreshTask == nil || selection != newSelection else { return }

        stop()

        selection = newSelection
        previousCPUTicks = nil
        isLoading = true
        let initialDelay = newSelection.contains(.cpu) ? 1.0 : 2.0

        refreshTask = Task { [weak self] in
            await self?.refresh()

            // Total CPU usage needs two tick samples; other metrics use the regular interval.
            try? await Task.sleep(for: .seconds(initialDelay))

            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        selection = []
        previousCPUTicks = nil
        isLoading = false
    }

    private func refresh() async {
        let requestedMetrics = selection
        guard !requestedMetrics.isEmpty else { return }
        guard let metrics = await XPCHelperClient.shared.systemMetrics(
            requesting: requestedMetrics
        ) else {
            isLoading = false
            return
        }
        guard !Task.isCancelled else { return }

        let currentTicks = CPUTickSnapshot(
            user: metrics.cpuUserTicks,
            system: metrics.cpuSystemTicks,
            idle: metrics.cpuIdleTicks,
            nice: metrics.cpuNiceTicks
        )

        sample = SystemActivitySample(
            cpuUsagePercent: requestedMetrics.contains(.cpu)
                ? cpuUsage(current: currentTicks, previous: previousCPUTicks)
                : nil,
            gpuUsagePercent: metrics.gpuUsagePercent,
            memoryUsedBytes: metrics.memoryUsedBytes,
            memoryTotalBytes: metrics.memoryTotalBytes,
            cpuTemperatureCelsius: metrics.cpuTemperatureCelsius,
            thermalState: metrics.thermalState
        )
        previousCPUTicks = requestedMetrics.contains(.cpu) ? currentTicks : nil
        isLoading = false
    }

    private func cpuUsage(current: CPUTickSnapshot, previous: CPUTickSnapshot?) -> Double? {
        guard let previous else { return nil }

        let user = UInt64(current.user &- previous.user)
        let system = UInt64(current.system &- previous.system)
        let idle = UInt64(current.idle &- previous.idle)
        let nice = UInt64(current.nice &- previous.nice)
        let busy = user + system + nice
        let total = busy + idle

        guard total > 0 else { return nil }
        return min(max(Double(busy) / Double(total) * 100, 0), 100)
    }
}
