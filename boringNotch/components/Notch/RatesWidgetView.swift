//
//  RatesWidgetView.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-10.
//
//  Currency / crypto rates panel for the Widgets tab.
//

import SwiftUI

struct RatesWidgetView: View {
    @ObservedObject var manager = RatesManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                Text("Rates")
                    .font(.headline)
            }
            .foregroundStyle(.white)

            if manager.rates.isEmpty {
                HStack(spacing: 6) {
                    if manager.statusMessage == nil {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(manager.statusMessage ?? "Loading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(manager.rates) { rate in
                    HStack(spacing: 6) {
                        Image(systemName: rate.isCrypto ? "bitcoinsign.circle" : "dollarsign.circle")
                            .font(.caption)
                            .foregroundStyle(rate.isCrypto ? .orange : .green)
                            .frame(width: 16)
                        Text(rate.pair)
                            .font(.caption)
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
                        Text(Self.format(rate.value))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .onAppear { manager.start() }
        .onDisappear { manager.stop() }
    }

    /// More decimals for small values (e.g. 0.8666), grouping for big ones (e.g. 103 250).
    private static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = value < 10 ? 4 : (value < 1000 ? 2 : 0)
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
