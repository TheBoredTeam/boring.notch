//
//  HomeWidgetsView.swift
//  boringNotch
//
//  Created by Maksymilian Wójcik on 2026-06-09.
//
//  A column of small, user-selectable widgets (chips) shown on the Home tab:
//  CPU temperature, weather, CPU/RAM/disk usage and a clock. Each chip is
//  toggled from Settings → Home.
//

import Defaults
import SwiftUI

struct HomeWidgetsView: View {
    @ObservedObject var monitor = SystemMonitorManager.shared
    @ObservedObject var weather = WeatherManager.shared

    @Default(.homeShowCPUTemp) var showCPUTemp
    @Default(.homeShowWeather) var showWeather
    @Default(.homeShowCPUUsage) var showCPUUsage
    @Default(.homeShowRAMUsage) var showRAMUsage
    @Default(.homeShowDiskUsage) var showDiskUsage
    @Default(.homeShowClock) var showClock
    @Default(.weatherUnit) var weatherUnit

    private var needsMonitor: Bool { showCPUTemp || showCPUUsage || showRAMUsage || showDiskUsage }

    var body: some View {
        HStack(spacing: 6) {
            if showClock {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    StatChip(
                        icon: "clock",
                        text: context.date.formatted(date: .omitted, time: .shortened),
                        tint: .white
                    )
                }
            }
            if showCPUTemp {
                StatChip(
                    icon: "thermometer.medium",
                    text: monitor.cpuTemperature.map { "\(Int($0.rounded()))°" } ?? "—",
                    tint: tempTint(monitor.cpuTemperature)
                )
            }
            if showWeather {
                StatChip(
                    icon: weather.symbolName,
                    text: weather.temperature.map { "\(Int($0.rounded()))\(weatherUnit.rawValue)" } ?? "…",
                    tint: .cyan
                )
            }
            if showCPUUsage {
                StatChip(icon: "cpu", text: "\(Int(monitor.cpuUsage * 100))%", tint: .green)
            }
            if showRAMUsage {
                StatChip(icon: "memorychip", text: "\(Int(monitor.memoryUsage * 100))%", tint: .blue)
            }
            if showDiskUsage {
                StatChip(icon: "internaldrive", text: "\(Int(monitor.diskUsage * 100))%", tint: .orange)
            }
        }
        .fixedSize()
        .onAppear {
            if needsMonitor { monitor.start() }
            if showWeather { weather.start() }
        }
        .onDisappear {
            if needsMonitor { monitor.stop() }
            if showWeather { weather.stop() }
        }
    }

    private func tempTint(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        switch value {
        case ..<60: return .green
        case ..<80: return .yellow
        default: return .red
        }
    }
}

private struct StatChip: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}
