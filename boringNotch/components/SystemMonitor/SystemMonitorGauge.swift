//
//  SystemMonitorGauge.swift
//  boringNotch
//
//  The ring gauge used by the system monitor cards, plus the much smaller
//  readout that can sit in the opened notch's header.
//

import SwiftUI

/// A donut gauge with a glyph in the middle.
///
/// Sweeps clockwise from 12 o'clock, which is the direction every other
/// progress ring on the platform turns — a gauge that runs the other way
/// reads as counting down.
struct SystemMonitorRing: View {
    var fraction: Double
    var tint: Color
    var systemImage: String
    var diameter: CGFloat = 42
    var lineWidth: CGFloat = 3.5
    /// Drawn hollow when there is no reading yet, so the first tick of a
    /// rate-based metric doesn't show a confident "0%".
    var isIndeterminate: Bool = false

    private var clamped: Double { min(1, max(0, fraction)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(SystemMonitorPalette.track, lineWidth: lineWidth)

            if !isIndeterminate {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.45), value: clamped)
            }

            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.28, weight: .medium))
                .foregroundStyle(isIndeterminate ? SystemMonitorPalette.label : tint)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// Compact CPU/memory pair for the opened notch's header — two thin bars and
/// their percentages, sized to sit alongside the battery indicator without
/// competing with it.
struct SystemMonitorHeaderGauges: View {
    @ObservedObject private var monitor = SystemMonitorManager.shared

    var body: some View {
        HStack(spacing: 8) {
            gauge(
                label: NSLocalizedString("system_metric_cpu_short", comment: "Abbreviated CPU label for the notch header"),
                fraction: monitor.snapshot.cpu?.load
            )
            gauge(
                label: NSLocalizedString("system_metric_memory_short", comment: "Abbreviated memory label for the notch header"),
                fraction: monitor.snapshot.memory?.fraction
            )
        }
        .onAppear { monitor.beginObserving() }
        .onDisappear { monitor.endObserving() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("System monitor"))
    }

    private func gauge(label: String, fraction: Double?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(SystemMonitorPalette.label)

            Capsule()
                .fill(SystemMonitorPalette.track)
                .frame(width: 26, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(loadTint(fraction ?? 0))
                        .frame(width: 26 * min(1, max(0, fraction ?? 0)), height: 4)
                        .animation(.easeOut(duration: 0.45), value: fraction ?? 0)
                }

            Text(fraction.map(SystemMetricFormatter.percent) ?? SystemMetricFormatter.unavailable)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .monospacedDigit()
                // A fixed width stops the header jittering as the number goes
                // 9% -> 10% -> 100%.
                .frame(width: 30, alignment: .leading)
        }
    }

    /// Green until things get busy, then amber, then red. The thresholds are
    /// deliberately high: a Mac sitting at 60% CPU is working, not in trouble.
    private func loadTint(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.75: return SystemMonitorPalette.positive
        case ..<0.9: return SystemMonitorPalette.warning
        default: return SystemMonitorPalette.critical
        }
    }
}
