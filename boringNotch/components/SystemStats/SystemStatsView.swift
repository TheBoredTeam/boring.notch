//
//  SystemStatsView.swift
//  boringNotch
//
//  Created by boringNotch contributors on 2026-04-19.
//

import SwiftUI

/// Full tab view for system stats inside the notch
struct SystemStatsTabView: View {
    @ObservedObject var stats = SystemStatsManager.shared

    var body: some View {
        HStack(spacing: 16) {
            // CPU gauge
            GaugeCard(
                title: "CPU",
                icon: "cpu",
                value: stats.cpuUsage,
                valueText: String(format: "%.0f%%", stats.cpuUsage),
                color: cpuColor
            )

            // RAM gauge
            GaugeCard(
                title: "Memory",
                icon: "memorychip",
                value: stats.memoryUsedPercent,
                valueText: String(format: "%.1f / %.0fG", stats.memoryUsedGB, stats.memoryTotalGB),
                color: memColor
            )

            // Thermal
            ThermalCard(state: stats.thermalState)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            stats.startMonitoring()
        }
    }

    private var cpuColor: Color {
        if stats.cpuUsage > 80 { return .red }
        if stats.cpuUsage > 50 { return .orange }
        return .cyan
    }

    private var memColor: Color {
        if stats.memoryUsedPercent > 85 { return .red }
        if stats.memoryUsedPercent > 70 { return .orange }
        return .purple
    }
}

/// Circular gauge card for CPU/RAM
struct GaugeCard: View {
    let title: String
    let icon: String
    let value: Double  // 0-100
    let valueText: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            // Circular gauge
            ZStack {
                // Background ring
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 5)

                // Progress ring
                Circle()
                    .trim(from: 0, to: min(max(value / 100, 0), 1))
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.6), color],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: value)

                // Center text
                VStack(spacing: 1) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(color)
                    Text(String(format: "%.0f", value))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("%")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: 72, height: 72)

            // Label
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(valueText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Thermal status card
struct ThermalCard: View {
    let state: ProcessInfo.ThermalState

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(thermalColor.opacity(0.12))
                    .frame(width: 72, height: 72)

                VStack(spacing: 4) {
                    Image(systemName: thermalIcon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(thermalColor)
                        .symbolEffect(.pulse, isActive: state == .critical)

                    Text(thermalLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(thermalColor)
                }
            }

            VStack(spacing: 2) {
                Text("Thermal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(thermalDetail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var thermalIcon: String {
        switch state {
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        case .serious: return "thermometer.high"
        case .critical: return "exclamationmark.triangle.fill"
        @unknown default: return "thermometer.low"
        }
    }

    private var thermalLabel: String {
        switch state {
        case .nominal: return "OK"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Throttle"
        @unknown default: return "?"
        }
    }

    private var thermalDetail: String {
        switch state {
        case .nominal: return "Running cool"
        case .fair: return "Slightly warm"
        case .serious: return "Performance limited"
        case .critical: return "Heavily throttled"
        @unknown default: return "Unknown"
        }
    }

    private var thermalColor: Color {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }
}

/// Compact header view (kept for optional header use)
struct SystemStatsHeaderView: View {
    @ObservedObject var stats = SystemStatsManager.shared

    var body: some View {
        HStack(spacing: 6) {
            StatPill(icon: "cpu", value: String(format: "%.0f%%", stats.cpuUsage), color: stats.cpuUsage > 50 ? .orange : .cyan)
            StatPill(icon: "memorychip", value: String(format: "%.1fG", stats.memoryUsedGB), color: stats.memoryUsedPercent > 70 ? .orange : .purple)
        }
    }
}

struct StatPill: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}
