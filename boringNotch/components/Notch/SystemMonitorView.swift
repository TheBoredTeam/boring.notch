//
//  SystemMonitorView.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-09.
//
//  Compact CPU / memory / network panel for the Widgets tab.
//

import Defaults
import SwiftUI

struct SystemMonitorView: View {
    @ObservedObject var monitor = SystemMonitorManager.shared
    @Default(.showCPUMonitor) var showCPU
    @Default(.showRAMMonitor) var showRAM
    @Default(.showNetworkMonitor) var showNetwork
    @Default(.showDiskMonitor) var showDisk
    @Default(.showTemperatureMonitor) var showTemperature

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                Text("System")
                    .font(.headline)
            }
            .foregroundStyle(.white)

            if showCPU {
                MonitorBar(
                    label: "CPU",
                    systemImage: "cpu",
                    value: monitor.cpuUsage,
                    detail: "\(Int(monitor.cpuUsage * 100))%",
                    tint: .green
                )
            }

            if showRAM {
                MonitorBar(
                    label: "RAM",
                    systemImage: "memorychip",
                    value: monitor.memoryUsage,
                    detail: String(
                        format: "%.1f/%.0f GB", monitor.memoryUsedGB, monitor.memoryTotalGB
                    ),
                    tint: .blue
                )
            }

            if showDisk {
                MonitorBar(
                    label: "Disk",
                    systemImage: "internaldrive",
                    value: monitor.diskUsage,
                    detail: String(
                        format: "%.0f/%.0f GB", monitor.diskUsedGB, monitor.diskTotalGB
                    ),
                    tint: .orange
                )
            }

            if showTemperature {
                HStack {
                    Label("CPU temp", systemImage: "thermometer.medium")
                        .font(.caption)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(monitor.cpuTemperature.map { "\(Int($0.rounded()))°C" } ?? "N/A")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if showNetwork {
                HStack(spacing: 12) {
                    Label(
                        SystemMonitorManager.formatRate(monitor.networkDownBytesPerSec),
                        systemImage: "arrow.down"
                    )
                    .foregroundStyle(.green)
                    Label(
                        SystemMonitorManager.formatRate(monitor.networkUpBytesPerSec),
                        systemImage: "arrow.up"
                    )
                    .foregroundStyle(.orange)
                    Spacer()
                }
                .font(.caption)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

private struct MonitorBar: View {
    let label: String
    let systemImage: String
    let value: Double
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(label, systemImage: systemImage)
                    .font(.caption)
                    .foregroundStyle(.white)
                Spacer()
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(2, geo.size.width * value))
                }
            }
            .frame(height: 6)
        }
    }
}
