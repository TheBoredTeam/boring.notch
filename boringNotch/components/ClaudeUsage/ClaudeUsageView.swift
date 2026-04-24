//
//  ClaudeUsageView.swift
//  boringNotch
//
//  AI usage widget for the expanded and closed notch
//

import SwiftUI

struct ClaudeUsageView: View {
    @ObservedObject var vm = ClaudeUsageViewModel.shared

    var body: some View {
        Group {
            if vm.providers.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(vm.providers.enumerated()), id: \.element.id) { index, provider in
                        ProviderUsageSection(provider: provider)

                        if index < vm.providers.count - 1 {
                            Divider()
                                .overlay(.white.opacity(0.08))
                        }
                    }
                }
                .padding(8)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 4)
        .frame(width: 158)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No provider data")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
            Text("Run claude-usage install --daemon")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ProviderUsageSection: View {
    let provider: UsageProviderDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                usageIcon(provider.iconName, size: 12, opacity: 0.75)

                Text(provider.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.82))

                if let planLabel = provider.planLabel {
                    Text(planLabel)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.08), in: Capsule())
                }

                Spacer()

                if let statusText = provider.statusText {
                    Text(statusText)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(statusColor(provider.statusLevel))
                }
            }

            if let errorText = provider.errorText {
                Text(errorText)
                    .font(.system(size: 9))
                    .foregroundColor(.red.opacity(0.8))
                    .lineLimit(2)
            } else {
                ForEach(provider.meters) { meter in
                    UsageMeterRow(meter: meter)
                }
            }

            if let creditsLabel = provider.creditsLabel {
                Text(creditsLabel)
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }
}

struct UsageMeterRow: View {
    let meter: UsageMeterDisplay

    private var color: Color {
        usageColor(for: meter)
    }

    private var fillFraction: CGFloat {
        meter.kind == .used ? CGFloat(meter.utilization) / 100 : CGFloat(100 - meter.utilization) / 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(meter.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Text(meter.kind == .remaining ? "\(meter.utilization)% left" : "\(meter.utilization)%")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.1))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * fillFraction, height: 4)
                }
            }
            .frame(height: 4)

            if let resetsIn = meter.resetsIn {
                Text("resets in \(resetsIn)")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }
}

struct ClaudeUsageCompactView: View {
    static let notchSpacerExtra: CGFloat = 34

    @ObservedObject var usageVM = ClaudeUsageViewModel.shared
    @EnvironmentObject var vm: BoringViewModel

    private var leftProviders: [UsageProviderDisplay] {
        let claudeProviders = usageVM.providers.filter { $0.id == "claude" }
        return claudeProviders.isEmpty ? Array(usageVM.providers.prefix(1)) : claudeProviders
    }

    private var rightProviders: [UsageProviderDisplay] {
        usageVM.providers.filter { provider in
            !leftProviders.contains { $0.id == provider.id }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(leftProviders) { provider in
                    CompactProviderBadge(
                        provider: provider,
                        includeReset: true,
                        isActive: false
                    )
                }
            }
            .padding(.leading, 2)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + Self.notchSpacerExtra)

            if usageVM.isStale {
                Text("stale")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.85))
            } else {
                HStack(spacing: 8) {
                    ForEach(rightProviders) { provider in
                        CompactProviderBadge(
                            provider: provider,
                            includeReset: true,
                            isActive: provider.id == usageVM.activeCompactProviderID
                        )
                    }
                }
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

struct ClaudeUsageClosedOverlay: View {
    @ObservedObject var usageVM = ClaudeUsageViewModel.shared

    var body: some View {
        if let provider = usageVM.activeCompactProvider {
            CompactProviderBadge(provider: provider, includeReset: true, isActive: true)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
    }
}

struct CompactProviderBadge: View {
    let provider: UsageProviderDisplay
    let includeReset: Bool
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            usageIcon(provider.iconName, size: 14, opacity: isActive ? 1.0 : 0.45)

            Text(provider.compactValueText)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(compactValueColor)

            if includeReset, let reset = provider.compactResetText {
                Text(reset)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, isActive ? 5 : 0)
        .padding(.vertical, isActive ? 3 : 0)
        .background(
            Capsule()
                .fill(.white.opacity(isActive ? 0.08 : 0))
        )
        .overlay(
            Capsule()
                .stroke(.white.opacity(isActive ? 0.12 : 0), lineWidth: 1)
        )
    }

    private var compactValueColor: Color {
        let base = provider.primaryMeter.map(usageColor(for:)) ?? .white.opacity(0.7)
        return isActive ? base : base.opacity(0.78)
    }
}

private func usageColor(for meter: UsageMeterDisplay) -> Color {
    if meter.kind == .remaining {
        if meter.utilization <= 10 { return .red }
        if meter.utilization <= 25 { return .orange }
        return .green
    }

    if meter.utilization >= 90 { return .red }
    if meter.utilization >= 75 { return .orange }
    return .green
}

private func statusColor(_ level: UsageAlertLevel) -> Color {
    switch level {
    case .critical:
        return .red
    case .warning:
        return .orange
    case .normal:
        return .white.opacity(0.45)
    }
}

private func usageIcon(_ name: String, size: CGFloat, opacity: Double) -> some View {
    let effectiveSize = name == "claude-icon" ? size + 3 : size

    return Image(name)
        .resizable()
        .renderingMode(.template)
        .foregroundColor(.white.opacity(opacity))
        .frame(width: effectiveSize, height: effectiveSize)
}
