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
                Image(systemName: "brain")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
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

// Compact view for the closed notch (live activity style)
struct ClaudeUsageCompactView: View {
    @ObservedObject var vm = ClaudeUsageViewModel.shared

    private var color: Color {
        if vm.sessionPct > 80 { return .red }
        if vm.sessionPct > 50 { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "brain")
                .font(.system(size: 9))
                .foregroundColor(color)
            Text("\(vm.sessionPct)%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
