import SwiftUI

/// Trigger button for a smart-home "scene" (Studio / Focus / Night / etc).
/// Single-shot — there is no persistent "active" state. Hover lifts and
/// brightens. Tap is animated as a subtle scale + accent flash.
struct SceneButton: View {
    let label: String
    let icon: String
    var action: () -> Void = {}

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Kairo.Space.sm) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isHovered ? Kairo.Palette.accent : Kairo.Palette.text)
                Text(label)
                    .font(Kairo.Typography.captionStrong)
                    .foregroundStyle(Kairo.Palette.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Kairo.Space.md + Kairo.Space.xs)
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
                    .strokeBorder(
                        isHovered ? Kairo.Palette.accent.opacity(0.40) : Kairo.Palette.glassStroke,
                        lineWidth: 0.5
                    )
            }
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .kairoElevation(isHovered ? Kairo.Elevation.hover : Kairo.Elevation.flat)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Kairo.Motion.hover) { isHovered = hovering }
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(Kairo.Motion.snappy) { isPressed = pressing }
            },
            perform: {}
        )
    }
}
