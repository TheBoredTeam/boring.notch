//
//  AIQuotaView.swift
//  boringNotch
//

import SwiftUI

struct AIQuotaView: View {
    @ObservedObject private var quotaManager = AIQuotaManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI Quota")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    Task {
                        await quotaManager.fetchAll()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(quotaManager.isLoading ? Color.secondary : Color.white)
                .disabled(quotaManager.isLoading)
                .help("Refresh AI quota")
            }

            HStack(spacing: 12) {
                QuotaCardView(
                    provider: .claude,
                    result: quotaManager.claudeQuota,
                    isLoading: quotaManager.isLoading
                )
                QuotaCardView(
                    provider: .codex,
                    result: quotaManager.codexQuota,
                    isLoading: quotaManager.isLoading
                )
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
