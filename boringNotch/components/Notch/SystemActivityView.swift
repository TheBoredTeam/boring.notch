//
//  SystemActivityView.swift
//  boringNotch
//

import AppKit
import Defaults
import SwiftUI

struct SystemActivityView: View {
    @ObservedObject private var monitor = SystemActivityMonitor.shared
    @Default(.systemActivityEnabled) private var systemActivityEnabled
    @Default(.showCPUActivityGauge) private var showCPUGauge
    @Default(.showGPUActivityGauge) private var showGPUGauge
    @Default(.showMemoryActivityGauge) private var showMemoryGauge
    @Default(.showCPUTemperatureGauge) private var showTemperatureGauge
    @State private var selectedProcessMetric: SystemActivityProcessMetric?
    @Namespace private var gaugeAnimation

    private var sample: SystemActivitySample { monitor.sample }

    var body: some View {
        Group {
            if requestedMetrics.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "gauge")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No system gauges selected")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("Choose gauges in System Activity settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let activeProcessMetric,
                      let selectedGauge = visibleGauges.first(where: {
                          $0.processMetric == activeProcessMetric
                      }) {
                HStack(spacing: 10) {
                    gaugeView(selectedGauge, selected: true)
                        .frame(width: 128)

                    ProcessListView(
                        metric: activeProcessMetric,
                        processes: monitor.processes,
                        isLoading: monitor.isProcessListLoading
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(visibleGauges) { gauge in
                        gaugeView(gauge, selected: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { updateMonitoring() }
        .onChange(of: requestedMetrics.rawValue) { _, _ in updateMonitoring() }
        .onChange(of: visibleProcessMetrics.rawValue) { _, visibleMetrics in
            guard let selectedProcessMetric,
                  visibleMetrics & selectedProcessMetric.processSelection.rawValue == 0
            else { return }
            self.selectedProcessMetric = nil
        }
        .onDisappear { monitor.stop() }
    }

    @ViewBuilder
    private func gaugeView(
        _ gauge: ActivityGaugeConfiguration,
        selected: Bool
    ) -> some View {
        if let processMetric = gauge.processMetric {
            Button {
                withAnimation(.smooth(duration: 0.35)) {
                    selectedProcessMetric = selected ? nil : processMetric
                }
            } label: {
                MetricGaugeCard(
                    title: gauge.title,
                    symbol: gauge.symbol,
                    value: gauge.value,
                    valueText: gauge.valueText,
                    detail: gauge.detail,
                    color: gauge.color,
                    scaleMaximum: gauge.scaleMaximum,
                    showsDisclosure: true,
                    isSelected: selected
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .matchedGeometryEffect(id: gauge.id, in: gaugeAnimation)
            .help(selected ? "Close process list" : "Show processes by \(gauge.title)")
            .accessibilityHint(selected ? "Closes the process list" : "Shows the process list")
        } else {
            MetricGaugeCard(
                title: gauge.title,
                symbol: gauge.symbol,
                value: gauge.value,
                valueText: gauge.valueText,
                detail: gauge.detail,
                color: gauge.color,
                scaleMaximum: gauge.scaleMaximum
            )
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }

    private var visibleGauges: [ActivityGaugeConfiguration] {
        var gauges: [ActivityGaugeConfiguration] = []

        if showCPUGauge {
            gauges.append(ActivityGaugeConfiguration(
                id: "cpu",
                title: "CPU",
                symbol: "cpu",
                value: sample.cpuUsagePercent,
                valueText: percentage(sample.cpuUsagePercent),
                detail: "Total usage",
                color: .blue,
                processMetric: .cpu
            ))
        }

        if showGPUGauge {
            gauges.append(ActivityGaugeConfiguration(
                id: "gpu",
                title: "GPU",
                symbol: "rectangle.3.group",
                value: sample.gpuUsagePercent,
                valueText: percentage(sample.gpuUsagePercent),
                detail: "Device usage",
                color: .purple,
                processMetric: .gpu
            ))
        }

        if showMemoryGauge {
            gauges.append(ActivityGaugeConfiguration(
                id: "memory",
                title: "Memory",
                symbol: "memorychip",
                value: sample.memoryUsagePercent,
                valueText: percentage(sample.memoryUsagePercent),
                detail: memoryDetail,
                color: .orange,
                processMetric: .memory
            ))
        }

        if showTemperatureGauge {
            gauges.append(ActivityGaugeConfiguration(
                id: "temperature",
                title: "CPU temp",
                symbol: "thermometer.medium",
                value: sample.cpuTemperatureCelsius,
                valueText: temperatureText,
                detail: sample.thermalStateLabel,
                color: temperatureColor,
                processMetric: nil
            ))
        }

        return gauges
    }

    private var activeProcessMetric: SystemActivityProcessMetric? {
        guard let selectedProcessMetric,
              visibleGauges.contains(where: { $0.processMetric == selectedProcessMetric })
        else { return nil }
        return selectedProcessMetric
    }

    private var visibleProcessMetrics: BNSystemMetricSelection {
        var selection: BNSystemMetricSelection = []
        if showCPUGauge { selection.insert(.cpuProcesses) }
        if showGPUGauge { selection.insert(.gpuProcesses) }
        if showMemoryGauge { selection.insert(.memoryProcesses) }
        return selection
    }

    private var requestedMetrics: BNSystemMetricSelection {
        guard systemActivityEnabled else { return [] }

        var selection: BNSystemMetricSelection = []
        if showCPUGauge { selection.insert(.cpu) }
        if showGPUGauge { selection.insert(.gpu) }
        if showMemoryGauge { selection.insert(.memory) }
        if showTemperatureGauge { selection.insert(.cpuTemperature) }
        if let activeProcessMetric { selection.insert(activeProcessMetric.processSelection) }
        return selection
    }

    private func updateMonitoring() {
        monitor.start(requesting: requestedMetrics)
    }

    private func percentage(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private var temperatureText: String {
        guard let temperature = sample.cpuTemperatureCelsius else { return "—" }
        return "\(Int(temperature.rounded()))°C"
    }

    private var memoryDetail: String {
        guard sample.memoryTotalBytes > 0 else { return "Physical memory" }
        let used = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: sample.memoryUsedBytes),
            countStyle: .memory
        )
        let total = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: sample.memoryTotalBytes),
            countStyle: .memory
        )
        return "\(used) / \(total)"
    }

    private var temperatureColor: Color {
        guard let temperature = sample.cpuTemperatureCelsius else { return .secondary }
        if temperature >= 80 { return .red }
        if temperature >= 60 { return .orange }
        return .blue
    }
}

private struct ActivityGaugeConfiguration: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let value: Double?
    let valueText: String
    let detail: String
    let color: Color
    let processMetric: SystemActivityProcessMetric?
    var scaleMaximum: Double = 100
}

private struct MetricGaugeCard: View {
    let title: String
    let symbol: String
    let value: Double?
    let valueText: String
    let detail: String
    let color: Color
    var scaleMaximum: Double = 100
    var showsDisclosure = false
    var isSelected = false

    private var progress: Double {
        guard let value, scaleMaximum > 0 else { return 0 }
        return min(max(value / scaleMaximum, 0), 1)
    }

    var body: some View {
        VStack(spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ArcGauge(progress: progress, valueText: valueText, color: color)
                .frame(width: 66, height: 66)

            Text(detail)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 112, maxWidth: 148, maxHeight: .infinity)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if showsDisclosure {
                Image(systemName: isSelected ? "chevron.left" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isSelected ? color : .secondary)
                    .padding(7)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? color.opacity(0.55) : .clear, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
    }
}

private struct ProcessListView: View {
    let metric: SystemActivityProcessMetric
    let processes: [SystemActivityProcess]
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: metric.symbol)
                    .foregroundStyle(metric.color)
                Text("Processes by \(metric.title)")
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                Text(metric.columnTitle)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 9, design: .rounded))
            .padding(.horizontal, 9)
            .frame(height: 22)

            Divider()
                .overlay(Color.white.opacity(0.08))

            if isLoading {
                VStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Measuring process usage…")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if processes.isEmpty {
                Text("No process usage reported")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(processes) { process in
                            ProcessUsageRow(process: process, metric: metric)
                            Divider()
                                .overlay(Color.white.opacity(0.045))
                                .padding(.leading, 30)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Processes sorted by \(metric.title)")
    }
}

private struct ProcessUsageRow: View {
    let process: SystemActivityProcess
    let metric: SystemActivityProcessMetric

    var body: some View {
        HStack(spacing: 6) {
            ProcessIcon(process: process)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 0) {
                Text(process.name)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .lineLimit(1)
                Text("PID \(process.pid)")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Text(valueText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(metric.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 25)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(process.name)
        .accessibilityValue(valueText)
    }

    private var valueText: String {
        let percentage = String(format: "%.1f%%", process.usagePercent)
        guard metric == .memory, let memoryBytes = process.memoryBytes else {
            return percentage
        }
        let bytes = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: memoryBytes),
            countStyle: .memory
        )
        return "\(percentage) · \(bytes)"
    }
}

private struct ProcessIcon: View {
    let process: SystemActivityProcess

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "gearshape.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var icon: NSImage? {
        if let runningIcon = NSRunningApplication(processIdentifier: process.pid)?.icon {
            return runningIcon
        }
        guard let path = process.executablePath else { return nil }
        if let applicationURL = applicationBundleURL(containing: path) {
            return NSWorkspace.shared.icon(forFile: applicationURL.path)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private func applicationBundleURL(containing executablePath: String) -> URL? {
        var candidate = URL(fileURLWithPath: executablePath)
        while candidate.path != "/" {
            if candidate.pathExtension.lowercased() == "app" {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }
}

private extension SystemActivityProcessMetric {
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "rectangle.3.group"
        case .memory: "memorychip"
        }
    }

    var columnTitle: String {
        switch self {
        case .cpu: "% CPU"
        case .gpu: "% GPU"
        case .memory: "% Memory"
        }
    }

    var color: Color {
        switch self {
        case .cpu: .blue
        case .gpu: .purple
        case .memory: .orange
        }
    }
}

private struct ArcGauge: View {
    let progress: Double
    let valueText: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: 0.75 * progress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .animation(.smooth(duration: 0.45), value: progress)

            Text(valueText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
        }
    }
}

#Preview {
    SystemActivityView()
        .frame(width: 600, height: 125)
        .padding()
        .background(.black)
        .preferredColorScheme(.dark)
}
