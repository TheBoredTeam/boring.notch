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

    private var previousCPUTicks: CPUTickSnapshot?
    private var refreshTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard refreshTask == nil else { return }

        previousCPUTicks = nil
        isLoading = sample.memoryTotalBytes == 0

        refreshTask = Task { [weak self] in
            await self?.refresh()

            // Total CPU usage needs two tick samples.
            try? await Task.sleep(for: .seconds(1))

            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        previousCPUTicks = nil
        isLoading = false
    }

    private func refresh() async {
        guard let metrics = await XPCHelperClient.shared.systemMetrics() else {
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
            cpuUsagePercent: cpuUsage(current: currentTicks, previous: previousCPUTicks),
            gpuUsagePercent: metrics.gpuUsagePercent,
            memoryUsedBytes: metrics.memoryUsedBytes,
            memoryTotalBytes: metrics.memoryTotalBytes,
            cpuTemperatureCelsius: metrics.cpuTemperatureCelsius,
            thermalState: metrics.thermalState
        )
        previousCPUTicks = currentTicks
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
