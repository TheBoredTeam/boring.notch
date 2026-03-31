//
//  ClaudeUsageView.swift
//  boringNotch
//
//  Claude usage widget for the expanded notch
//

import SwiftUI

struct ClaudeUsageView: View {
    @ObservedObject var vm = ClaudeUsageViewModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 4) {
                Image("claude-icon")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 12, height: 12)
                Text("Claude")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                if vm.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                }
            }

            // Usage meters
            ForEach(vm.meters) { meter in
                UsageMeterRow(meter: meter)
            }

            // Extra usage
            if vm.extraUsageEnabled && vm.extraUsageCredits > 0 {
                HStack {
                    Text("Extra")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Text(String(format: "$%.2f", vm.extraUsageCredits))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(.vertical, 4)
        .frame(width: 130)
    }
}

struct UsageMeterRow: View {
    let meter: UsageMeterDisplay

    private var color: Color {
        if meter.utilization > 80 { return .red }
        if meter.utilization > 50 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(meter.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("\(meter.utilization)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.1))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(meter.utilization) / 100, height: 4)
                }
            }
            .frame(height: 4)

            // Reset time
            if let resetsIn = meter.resetsIn {
                Text("resets in \(resetsIn)")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }
}

// Compact view for the closed notch (standalone, no music playing)
// Mirrors MusicLiveActivity layout: left content | notch gap | right content
struct ClaudeUsageCompactView: View {
    @ObservedObject var usageVM = ClaudeUsageViewModel.shared
    @EnvironmentObject var vm: BoringViewModel

    private var sessionColor: Color { usageColor(usageVM.sessionPct) }
    private var weeklyColor: Color { usageColor(usageVM.weeklyPct) }
    private var showWeekly: Bool { usageVM.weeklyPct >= 75 }

    var body: some View {
        HStack(spacing: 0) {
            // Left side: Claude icon + session %
            HStack(spacing: 3) {
                claudeIcon
                Text("\(usageVM.sessionPct)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(sessionColor)
                if let reset = usageVM.meters.first?.resetsIn {
                    Text(reset)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            .frame(
                width: max(0, vm.effectiveClosedNotchHeight - 12) + 60,
                height: max(0, vm.effectiveClosedNotchHeight - 12),
                alignment: .center
            )

            // Middle gap (black, spans the notch)
            Rectangle()
                .fill(.black)
                .frame(
                    width: vm.closedNotchSize.width - 10,
                    height: vm.effectiveClosedNotchHeight
                )

            // Right side: weekly (only if >= 75%)
            if showWeekly {
                HStack(spacing: 3) {
                    Text("7d")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(usageVM.weeklyPct)%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(weeklyColor)
                }
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12) + 30,
                    height: max(0, vm.effectiveClosedNotchHeight - 12),
                    alignment: .center
                )
            } else {
                // Empty spacer to keep layout balanced
                Rectangle().fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
            }
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }
}

// Overlay that shows ALONGSIDE the music live activity
// Positioned to the far right of the notch area
struct ClaudeUsageClosedOverlay: View {
    @ObservedObject var usageVM = ClaudeUsageViewModel.shared

    private var sessionColor: Color { usageColor(usageVM.sessionPct) }

    var body: some View {
        HStack(spacing: 3) {
            claudeIcon
            Text("\(usageVM.sessionPct)%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(sessionColor)
            if let reset = usageVM.meters.first?.resetsIn {
                Text(reset)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}

// Shared helpers
private func usageColor(_ pct: Int) -> Color {
    if pct > 80 { return .red }
    if pct > 50 { return .orange }
    return .green
}

private var claudeIcon: some View {
    Image("claude-icon")
        .resizable()
        .renderingMode(.template)
        .foregroundColor(.white.opacity(0.7))
        .frame(width: 12, height: 12)
}
