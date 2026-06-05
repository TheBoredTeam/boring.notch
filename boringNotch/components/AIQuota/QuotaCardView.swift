//
//  QuotaCardView.swift
//  boringNotch
//

import SwiftUI

struct QuotaCardView: View {
    let provider: AIProvider
    let result: AIQuotaResult?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if isLoading && result == nil {
                loadingState
            } else if let result, result.success {
                quotaRows(result.tiers)
                resetText(result.tiers)
            } else {
                statusState(result)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: provider.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text(provider.displayName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            statusDot
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        if let result, result.success {
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
        } else if result != nil {
            Circle()
                .fill(Color.orange)
                .frame(width: 7, height: 7)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 12)
            ProgressView()
                .controlSize(.small)
            Text("Loading")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func quotaRows(_ tiers: [QuotaTier]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(tiers.prefix(4)) { tier in
                HStack(spacing: 8) {
                    Text(tierLabel(tier.name))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .leading)
                    QuotaProgressBar(utilization: tier.utilization)
                    Text("\(Int(tier.utilization.rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private func resetText(_ tiers: [QuotaTier]) -> some View {
        if let nextReset = tiers.compactMap(\.resetsAt).filter({ $0 > Date() }).min() {
            Text("Resets in \(relativeResetTime(nextReset))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text("Reset time unavailable")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func statusState(_ result: AIQuotaResult?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 12)
            Text(statusTitle(result))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(statusMessage(result))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func tierLabel(_ name: String) -> String {
        switch name {
        case "five_hour":
            return "5h"
        case "seven_day":
            return "7d"
        case "seven_day_opus":
            return "Opus"
        case "seven_day_sonnet":
            return "Sonnet"
        default:
            return name.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func relativeResetTime(_ date: Date) -> String {
        Self.resetFormatter.string(from: Date(), to: date) ?? "--"
    }

    private func statusTitle(_ result: AIQuotaResult?) -> String {
        switch result?.credentialStatus {
        case .notFound:
            return "Credentials not found"
        case .expired:
            return "Token expired"
        case .parseError:
            return "Credentials unreadable"
        case .valid:
            return "Usage unavailable"
        case nil:
            return "No data"
        }
    }

    private func statusMessage(_ result: AIQuotaResult?) -> String {
        if let error = result?.error, !error.isEmpty {
            return error
        }

        switch provider {
        case .claude:
            return "Run claude to login again."
        case .codex:
            return "Run codex login with ChatGPT auth."
        }
    }

    private static let resetFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()
}
