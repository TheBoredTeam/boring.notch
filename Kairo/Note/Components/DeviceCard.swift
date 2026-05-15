import SwiftUI

/// Light / switch / sensor tile. Shows current state at a glance:
/// on-state lights up the icon in accent color and adds a soft glow ring;
/// off-state stays subdued. Hover lifts the card subtly.
struct DeviceCard: View {
    let name: String
    let value: String
    let icon: String
    let on: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            iconBadge
            VStack(alignment: .leading, spacing: Kairo.Space.xxs) {
                Text(name)
                    .font(Kairo.Typography.bodyEmphasis)
                    .foregroundStyle(Kairo.Palette.text)
                Text(value)
                    .font(Kairo.Typography.bodySmall)
                    .foregroundStyle(on ? Kairo.Palette.accent : Kairo.Palette.textDim)
            }
        }
        .padding(Kairo.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                        .fill(Kairo.Palette.glassTint.opacity(isHovered ? 1.5 : 1.0))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .strokeBorder(
                    on ? Kairo.Palette.accent.opacity(0.35) : Kairo.Palette.glassStroke,
                    lineWidth: 0.5
                )
        }
        .kairoElevation(isHovered ? Kairo.Elevation.hover : Kairo.Elevation.flat)
        .onHover { hovering in
            withAnimation(Kairo.Motion.hover) { isHovered = hovering }
        }
        .animation(Kairo.Motion.snappy, value: on)
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(on ? Kairo.Palette.accent.opacity(0.18) : Kairo.Palette.surfaceHi)
                .frame(width: 32, height: 32)
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Kairo.Palette.accent : Kairo.Palette.textDim)
        }
        .overlay {
            // Soft glow ring when on — communicates state at a glance
            if on {
                Circle()
                    .stroke(Kairo.Palette.accent.opacity(0.30), lineWidth: 6)
                    .frame(width: 32, height: 32)
                    .blur(radius: 6)
            }
        }
    }
}
