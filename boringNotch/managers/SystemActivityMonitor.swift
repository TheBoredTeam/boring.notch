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

enum SystemActivityProcessMetric: String, Sendable {
    case cpu
    case gpu
    case memory

    var processSelection: BNSystemMetricSelection {
        switch self {
        case .cpu: .cpuProcesses
        case .gpu: .gpuProcesses
        case .memory: .memoryProcesses
        }
    }
}

enum SystemActivityMonitorClient: Hashable, Sendable {
    case systemTab
    case mainCard
}

struct SystemActivityProcess: Identifiable, Sendable {
    let pid: Int32
    let name: String
    let executablePath: String?
    let usagePercent: Double
    let memoryBytes: UInt64?

    var id: Int32 { pid }
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
    @Published private(set) var processes: [SystemActivityProcess] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isProcessListLoading = false

    private var selection: BNSystemMetricSelection = []
    private var clientSelections: [SystemActivityMonitorClient: BNSystemMetricSelection] = [:]
    private var previousCPUTicks: CPUTickSnapshot?
    private var previousGPUProcessTimes: [Int32: UInt64] = [:]
    private var previousGPUUptimeNanoseconds: UInt64?
    private var refreshTask: Task<Void, Never>?

    private init() {}

    func start(
        requesting newSelection: BNSystemMetricSelection,
        for client: SystemActivityMonitorClient
    ) {
        if newSelection.isEmpty {
            clientSelections.removeValue(forKey: client)
        } else {
            clientSelections[client] = newSelection
        }
        updateSelection()
    }

    func stop(for client: SystemActivityMonitorClient) {
        clientSelections.removeValue(forKey: client)
        updateSelection()
    }

    private func updateSelection() {
        let combinedSelection = clientSelections.values.reduce(
            into: BNSystemMetricSelection()
        ) { result, requestedSelection in
            result.formUnion(requestedSelection)
        }
        restart(requesting: combinedSelection)
    }

    private func restart(requesting newSelection: BNSystemMetricSelection) {
        guard !newSelection.isEmpty else {
            stopMonitoring()
            return
        }
        guard refreshTask == nil || selection != newSelection else { return }

        let keepsCPUBaseline = selection.contains(.cpu) && newSelection.contains(.cpu)
        let existingCPUTicks = keepsCPUBaseline ? previousCPUTicks : nil
        refreshTask?.cancel()
        refreshTask = nil

        selection = newSelection
        previousCPUTicks = existingCPUTicks
        previousGPUProcessTimes = [:]
        previousGPUUptimeNanoseconds = nil
        processes = []
        isLoading = true
        isProcessListLoading = processMetric(for: newSelection) != nil
        let needsFollowUpSample = newSelection.contains(.cpu)
            || newSelection.contains(.gpuProcesses)
        let initialDelay = needsFollowUpSample ? 1.0 : 2.0

        refreshTask = Task { [weak self] in
            await self?.refresh()

            // Total CPU and per-process GPU usage need two counter samples.
            try? await Task.sleep(for: .seconds(initialDelay))

            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
        selection = []
        previousCPUTicks = nil
        previousGPUProcessTimes = [:]
        previousGPUUptimeNanoseconds = nil
        processes = []
        isLoading = false
        isProcessListLoading = false
    }

    private func refresh() async {
        let requestedMetrics = selection
        guard !requestedMetrics.isEmpty else { return }
        guard let metrics = await XPCHelperClient.shared.systemMetrics(
            requesting: requestedMetrics
        ) else {
            isLoading = false
            isProcessListLoading = false
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
        updateProcesses(from: metrics, requesting: requestedMetrics)
        isLoading = false
    }

    private func updateProcesses(
        from metrics: BNSystemMetricPayload,
        requesting requestedMetrics: BNSystemMetricSelection
    ) {
        guard let metric = processMetric(for: requestedMetrics) else {
            processes = []
            isProcessListLoading = false
            return
        }

        switch metric {
        case .cpu:
            processes = metrics.processes.compactMap { process in
                guard let usage = process.cpuUsagePercent else { return nil }
                return SystemActivityProcess(
                    pid: process.pid,
                    name: process.name,
                    executablePath: process.executablePath,
                    usagePercent: usage,
                    memoryBytes: nil
                )
            }
            .sorted(by: processUsageSort)
            isProcessListLoading = false

        case .memory:
            let totalMemory = metrics.memoryTotalBytes
            processes = metrics.processes.compactMap { process in
                guard let memoryBytes = process.memoryBytes, totalMemory > 0 else { return nil }
                return SystemActivityProcess(
                    pid: process.pid,
                    name: process.name,
                    executablePath: process.executablePath,
                    usagePercent: Double(memoryBytes) / Double(totalMemory) * 100,
                    memoryBytes: memoryBytes
                )
            }
            .sorted(by: processUsageSort)
            isProcessListLoading = false

        case .gpu:
            let currentTimes = Dictionary(
                uniqueKeysWithValues: metrics.processes.compactMap { process in
                    process.gpuTimeNanoseconds.map { (process.pid, $0) }
                }
            )
            defer {
                previousGPUProcessTimes = currentTimes
                previousGPUUptimeNanoseconds = metrics.sampleUptimeNanoseconds
            }

            guard let previousUptime = previousGPUUptimeNanoseconds,
                  metrics.sampleUptimeNanoseconds > previousUptime
            else {
                processes = []
                isProcessListLoading = true
                return
            }

            let elapsed = Double(metrics.sampleUptimeNanoseconds - previousUptime)
            processes = metrics.processes.compactMap { process in
                guard let current = process.gpuTimeNanoseconds,
                      let previous = previousGPUProcessTimes[process.pid]
                else { return nil }
                let delta = current >= previous ? current - previous : 0
                let usage = min(max(Double(delta) / elapsed * 100, 0), 100)
                return SystemActivityProcess(
                    pid: process.pid,
                    name: process.name,
                    executablePath: process.executablePath,
                    usagePercent: usage,
                    memoryBytes: nil
                )
            }
            .sorted(by: processUsageSort)
            isProcessListLoading = false
        }
    }

    private func processMetric(
        for selection: BNSystemMetricSelection
    ) -> SystemActivityProcessMetric? {
        if selection.contains(.cpuProcesses) { return .cpu }
        if selection.contains(.gpuProcesses) { return .gpu }
        if selection.contains(.memoryProcesses) { return .memory }
        return nil
    }

    private func processUsageSort(
        _ lhs: SystemActivityProcess,
        _ rhs: SystemActivityProcess
    ) -> Bool {
        if lhs.usagePercent == rhs.usagePercent {
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return lhs.usagePercent > rhs.usagePercent
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
