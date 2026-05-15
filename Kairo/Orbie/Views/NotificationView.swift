import SwiftUI

struct NotificationData: Hashable {
    let app: String
    let title: String
    let body: String
    let icon: String
    let timestamp: String
}

/// Card-sized notification popup — Orbie auto-dismisses this after 6s
/// per ViewRegistry. Bigger and more prominent than the inline row
/// shown in the Note window's NotificationCenterView.
struct NotificationView: View {
    let data: NotificationData

    var body: some View {
        HStack(alignment: .top, spacing: Kairo.Space.lg) {
            iconView

            VStack(alignment: .leading, spacing: Kairo.Space.xs) {
                HStack(spacing: Kairo.Space.sm) {
                    Text(data.app.uppercased())
                        .font(Kairo.Typography.captionStrong)
                        .tracking(1.2)
                        .foregroundStyle(Kairo.Palette.textDim)
                    Spacer(minLength: 0)
                    Text(data.timestamp)
                        .font(Kairo.Typography.monoSmall)
                        .foregroundStyle(Kairo.Palette.textFaint)
                }

                Text(data.title)
                    .font(Kairo.Typography.title)
                    .foregroundStyle(Kairo.Palette.text)
                    .lineLimit(2)

                Text(data.body)
                    .font(Kairo.Typography.body)
                    .foregroundStyle(Kairo.Palette.textDim)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Kairo.Space.xl)
    }

    @ViewBuilder
    private var iconView: some View {
        if isLikelySFSymbol(data.icon) {
            ZStack {
                Circle()
                    .fill(Kairo.Palette.accent.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: data.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Kairo.Palette.accent)
            }
        } else {
            Text(data.icon)
                .font(.system(size: 40))
                .frame(width: 48, height: 48)
        }
    }

    private func isLikelySFSymbol(_ s: String) -> Bool {
        s.allSatisfy { $0.isASCII } && s.contains(".")
    }
}
