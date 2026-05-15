import SwiftUI

struct QuickAnswerData: Hashable {
    let text: String
    let icon: String?
}

/// Pill-sized one-liner answer. Optional leading icon (emoji or SF Symbol).
/// Auto-dismisses after 8s per ViewRegistry.
struct QuickAnswerView: View {
    let data: QuickAnswerData

    var body: some View {
        HStack(spacing: Kairo.Space.md) {
            if let icon = data.icon, !icon.isEmpty {
                iconView(icon)
            }
            Text(data.text)
                .font(Kairo.Typography.bodyEmphasis)
                .foregroundStyle(Kairo.Palette.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Kairo.Space.xl)
        .padding(.vertical, Kairo.Space.md)
    }

    @ViewBuilder
    private func iconView(_ icon: String) -> some View {
        if isLikelySFSymbol(icon) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Kairo.Palette.accent)
                .frame(width: 28)
        } else {
            Text(icon).font(.system(size: 24)).frame(width: 28)
        }
    }

    private func isLikelySFSymbol(_ s: String) -> Bool {
        s.allSatisfy { $0.isASCII } && s.contains(".")
    }
}
