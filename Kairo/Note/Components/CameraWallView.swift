import SwiftUI

/// Grid of camera feeds. Placeholder layout for now — real video streams
/// will be plumbed in by the smart-home integration. Each tile renders a
/// glass card with a LIVE pill, time-of-day gradient, and the camera name.
struct CameraWallView: View {
    private let cameras: [CameraFeed] = [
        .init(name: "Front Door", isLive: true,  signal: .strong),
        .init(name: "Studio",     isLive: true,  signal: .strong),
        .init(name: "Backyard",   isLive: false, signal: .offline),
        .init(name: "Garage",     isLive: true,  signal: .weak)
    ]

    private let columns = [
        GridItem(.flexible(), spacing: Kairo.Space.sm),
        GridItem(.flexible(), spacing: Kairo.Space.sm)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Kairo.Space.sm) {
                ForEach(cameras) { camera in
                    CameraTile(camera: camera)
                }
            }
            .padding(.horizontal, Kairo.Space.lg)
            .padding(.vertical, Kairo.Space.md)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Models

private struct CameraFeed: Identifiable {
    enum Signal { case strong, weak, offline }
    let name: String
    let isLive: Bool
    let signal: Signal
    var id: String { name }
}

// MARK: - Tile

private struct CameraTile: View {
    let camera: CameraFeed
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            placeholderFeed
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    statusPill
                    Spacer()
                    signalIndicator
                }
                .padding(Kairo.Space.sm)
                Spacer()
                Text(camera.name)
                    .font(Kairo.Typography.captionStrong)
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
                    .padding(Kairo.Space.sm)
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .strokeBorder(Kairo.Palette.glassStroke, lineWidth: 0.5)
        }
        .kairoElevation(isHovered ? Kairo.Elevation.hover : Kairo.Elevation.flat)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(Kairo.Motion.hover, value: isHovered)
        .onHover { isHovered = $0 }
    }

    /// Time-of-day gradient as a stand-in for a real video frame. Looks
    /// like a feed at dusk/dawn — feels like a camera feed, not a chrome box.
    private var placeholderFeed: some View {
        LinearGradient(
            colors: camera.isLive
                ? [Color(red: 0.15, green: 0.20, blue: 0.30),
                   Color(red: 0.06, green: 0.08, blue: 0.14)]
                : [Color(red: 0.10, green: 0.10, blue: 0.11),
                   Color(red: 0.06, green: 0.06, blue: 0.07)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            // Subtle scanline / video grain
            if camera.isLive {
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.clear,
                             Color.white.opacity(0.03), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var statusPill: some View {
        Group {
            if camera.isLive {
                KairoPill("LIVE", icon: "dot.radiowaves.left.and.right", tone: .accent)
            } else {
                KairoPill("OFFLINE", icon: "wifi.slash", tone: .danger)
            }
        }
    }

    private var signalIndicator: some View {
        let symbol: String = {
            switch camera.signal {
            case .strong:  return "wifi"
            case .weak:    return "wifi.exclamationmark"
            case .offline: return "wifi.slash"
            }
        }()
        let tint: Color = {
            switch camera.signal {
            case .strong:  return Color.white.opacity(0.85)
            case .weak:    return Kairo.Palette.accent
            case .offline: return Kairo.Palette.danger
            }
        }()
        return Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
    }
}
