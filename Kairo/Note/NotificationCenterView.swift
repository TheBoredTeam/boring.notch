import SwiftUI

/// Scrollable list of incoming notifications. Renders an inviting empty
/// state when there's nothing to show. Each row is a glass card with a
/// proper info hierarchy: app pill → title → body, and a timestamp.
struct NotificationCenterView: View {
    @ObservedObject var bridge: KairoNotificationBridge

    var body: some View {
        ScrollView {
            if bridge.items.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: Kairo.Space.sm) {
                    ForEach(bridge.items, id: \.self) { item in
                        NotificationRow(item: item, onDismiss: { bridge.dismiss(item) })
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal:   .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
                .padding(.horizontal, Kairo.Space.md)
                .padding(.vertical, Kairo.Space.md)
                .animation(Kairo.Motion.snappy, value: bridge.items)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Kairo.Space.md) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Kairo.Palette.textFaint)

            VStack(spacing: Kairo.Space.xs) {
                Text("All caught up")
                    .font(Kairo.Typography.titleSmall)
                Text("Notifications will appear here")
                    .font(Kairo.Typography.bodySmall)
                    .foregroundStyle(Kairo.Palette.textDim)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Kairo.Space.xxxl + Kairo.Space.xl)
        .padding(.bottom, Kairo.Space.xxxl)
    }
}

// MARK: - Row

private struct NotificationRow: View {
    let item: NotificationData
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Kairo.Space.md) {
            // App icon — either an SF Symbol or an emoji
            iconView

            VStack(alignment: .leading, spacing: Kairo.Space.xxs) {
                // Top row: app name + timestamp
                HStack(spacing: Kairo.Space.sm) {
                    Text(item.app.uppercased())
                        .font(Kairo.Typography.captionStrong)
                        .tracking(0.8)
                        .foregroundStyle(Kairo.Palette.textDim)
                    Spacer(minLength: 0)
                    Text(item.timestamp)
                        .font(Kairo.Typography.monoSmall)
                        .foregroundStyle(Kairo.Palette.textFaint)
                }

                Text(item.title)
                    .font(Kairo.Typography.bodyEmphasis)
                    .foregroundStyle(Kairo.Palette.text)
                    .lineLimit(1)

                Text(item.body)
                    .font(Kairo.Typography.bodySmall)
                    .foregroundStyle(Kairo.Palette.textDim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Kairo.Space.md)
        .background {
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                        .fill(Kairo.Palette.glassTint.opacity(isHovered ? 1.6 : 1.0))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .strokeBorder(Kairo.Palette.glassStroke, lineWidth: 0.5)
        }
        .onHover { hovering in
            withAnimation(Kairo.Motion.hover) { isHovered = hovering }
        }
        .contextMenu {
            Button("Dismiss", role: .destructive, action: onDismiss)
        }
    }

    /// If the icon string looks like an SF Symbol (no whitespace, no emoji),
    /// render it as one. Otherwise treat as a literal text glyph (emoji).
    @ViewBuilder
    private var iconView: some View {
        if isLikelySFSymbol(item.icon) {
            Image(systemName: item.icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Kairo.Palette.accent)
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(Kairo.Palette.accent.opacity(0.12))
                }
        } else {
            Text(item.icon)
                .font(.system(size: 26))
                .frame(width: 32, height: 32)
        }
    }

    private func isLikelySFSymbol(_ s: String) -> Bool {
        // SF Symbols are lowercase alphanumerics with dots. Emojis contain
        // characters outside ASCII range.
        s.allSatisfy { $0.isASCII } && s.contains(".")
    }
}
