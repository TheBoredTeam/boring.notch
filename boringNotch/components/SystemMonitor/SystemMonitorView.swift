//
//  SystemMonitorView.swift
//  boringNotch
//
//  Created by Zaky Syihab Hatmoko on 05/03/2026.
//

import SwiftUI

// MARK: - Color Coding

/// Returns a color based on usage level and thresholds.
/// - Parameters:
///   - value: Usage percentage (0-100).
///   - thresholds: A tuple of (warning, critical) thresholds.
private func colorForUsage(_ value: Double, thresholds: (Double, Double)) -> Color {
    switch value {
    case ..<thresholds.0:
        return .green
    case thresholds.0..<thresholds.1:
        return .yellow
    default:
        return .red
    }
}

/// Convenience accessors for color-coded usage values.
extension SystemMonitorManager {
    var cpuColor: Color {
        colorForUsage(cpuUsage, thresholds: (50, 80))
    }

    var memoryColor: Color {
        colorForUsage(memoryUsagePercent, thresholds: (70, 85))
    }
}

// MARK: - Gauge Ring

/// A small circular gauge ring with an SF Symbol icon centered inside.
private struct GaugeRingView: View {
    let progress: Double
    let color: Color
    let iconName: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: iconName)
                .font(.system(size: 6, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(width: 18, height: 18)
    }
}

// MARK: - Header Indicator

/// Compact system monitor indicator for the notch header.
/// Displays CPU and memory usage as small circular gauge rings with color coding.
/// Clicking shows a popover with detailed stats and an option to open Activity Monitor.
struct SystemMonitorView: View {
    @ObservedObject var monitor = SystemMonitorManager.shared
    @EnvironmentObject var vm: BoringViewModel
    @State private var showPopover = false
    @State private var isHoveringPopover = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        Button(action: {
            withAnimation {
                showPopover.toggle()
            }
        }) {
            HStack(spacing: 10) {
                GaugeRingView(progress: monitor.cpuUsage, color: monitor.cpuColor, iconName: "cpu")
                GaugeRingView(progress: monitor.memoryUsagePercent, color: monitor.memoryColor, iconName: "memorychip")
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            SystemMonitorMenuView(onDismiss: { showPopover = false })
                .onHover { hovering in
                    isHoveringPopover = hovering
                    if hovering {
                        hideTask?.cancel()
                        hideTask = nil
                    } else {
                        scheduleHideIfNeeded()
                    }
                }
        }
        .onChange(of: showPopover) {
            vm.isSystemMonitorPopoverActive = showPopover
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
        }
    }

    // MARK: - Hover Persistence

    private func scheduleHideIfNeeded() {
        guard !isHoveringPopover else { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { showPopover = false } }
        }
    }
}

// MARK: - Popover Menu

/// Detailed system monitor popover shown when clicking the gauge rings.
struct SystemMonitorMenuView: View {
    @ObservedObject var monitor = SystemMonitorManager.shared
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("System Monitor")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                statRow(label: "CPU Usage", icon: "cpu", value: "\(Int(monitor.cpuUsage))%", color: monitor.cpuColor)
                statRow(label: "Memory Usage", icon: "memorychip", value: "\(Int(monitor.memoryUsagePercent))%", color: monitor.memoryColor)

                HStack {
                    Text("Memory Used")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f / %.0f GB", monitor.memoryUsed, monitor.memoryTotal))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)

            Divider().background(Color.white)

            Button(action: openActivityMonitor) {
                Label("Activity Monitor", systemImage: "gauge.with.dots.needle.33percent")
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
        .padding()
        .frame(width: 280)
        .foregroundColor(.white)
    }

    private func statRow(label: String, icon: String, value: String, color: Color) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }

    private func openActivityMonitor() {
        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        )
        onDismiss()
    }
}

#Preview {
    SystemMonitorView()
        .environmentObject(BoringViewModel())
        .padding()
        .background(Color.black)
}
