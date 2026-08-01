//
//  SystemActivityView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct SystemActivityView: View {
    @ObservedObject private var monitor = SystemActivityMonitor.shared
    @Default(.systemActivityEnabled) private var systemActivityEnabled
    @Default(.showCPUActivityGauge) private var showCPUGauge
    @Default(.showGPUActivityGauge) private var showGPUGauge
    @Default(.showMemoryActivityGauge) private var showMemoryGauge
    @Default(.showCPUTemperatureGauge) private var showTemperatureGauge

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
            } else {
                HStack(spacing: 8) {
                    if showCPUGauge {
                        MetricGaugeCard(
                            title: "CPU",
                            symbol: "cpu",
                            value: sample.cpuUsagePercent,
                            valueText: percentage(sample.cpuUsagePercent),
                            detail: "Total usage",
                            color: .blue
                        )
                    }

                    if showGPUGauge {
                        MetricGaugeCard(
                            title: "GPU",
                            symbol: "rectangle.3.group",
                            value: sample.gpuUsagePercent,
                            valueText: percentage(sample.gpuUsagePercent),
                            detail: "Device usage",
                            color: .purple
                        )
                    }

                    if showMemoryGauge {
                        MetricGaugeCard(
                            title: "Memory",
                            symbol: "memorychip",
                            value: sample.memoryUsagePercent,
                            valueText: percentage(sample.memoryUsagePercent),
                            detail: memoryDetail,
                            color: .orange
                        )
                    }

                    if showTemperatureGauge {
                        MetricGaugeCard(
                            title: "CPU temp",
                            symbol: "thermometer.medium",
                            value: sample.cpuTemperatureCelsius,
                            valueText: temperatureText,
                            detail: sample.thermalStateLabel,
                            color: temperatureColor,
                            scaleMaximum: 100
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .onAppear { updateMonitoring() }
        .onChange(of: requestedMetrics.rawValue) { _, _ in updateMonitoring() }
        .onDisappear { monitor.stop() }
    }

    private var requestedMetrics: BNSystemMetricSelection {
        guard systemActivityEnabled else { return [] }

        var selection: BNSystemMetricSelection = []
        if showCPUGauge { selection.insert(.cpu) }
        if showGPUGauge { selection.insert(.gpu) }
        if showMemoryGauge { selection.insert(.memory) }
        if showTemperatureGauge { selection.insert(.cpuTemperature) }
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

private struct MetricGaugeCard: View {
    let title: String
    let symbol: String
    let value: Double?
    let valueText: String
    let detail: String
    let color: Color
    var scaleMaximum: Double = 100

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
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
