import SwiftUI

/// Top-level shell for the floating Note window. Three tabs: alerts, home,
/// cameras. Glass background, segmented tab bar with a sliding accent
/// indicator. Uses Phase 1 design system tokens throughout.
struct NoteShell: View {
    @StateObject private var bridge = KairoNotificationBridge()
    @State private var tab: Tab = .notifications
    @Namespace private var tabIndicator

    enum Tab: Hashable, CaseIterable {
        case notifications, home, cameras

        var label: String {
            switch self {
            case .notifications: return "Alerts"
            case .home:          return "Home"
            case .cameras:       return "Cameras"
            }
        }

        var icon: String {
            switch self {
            case .notifications: return "bell.fill"
            case .home:          return "house.fill"
            case .cameras:       return "video.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Kairo.Space.lg)
                .padding(.top, Kairo.Space.lg)
                .padding(.bottom, Kairo.Space.md)

            Rectangle()
                .fill(Kairo.Palette.hairline)
                .frame(height: 0.5)

            content
                .padding(.top, Kairo.Space.md)
        }
        .background {
            // Glass surface with subtle inner highlight + outer hairline
            RoundedRectangle(cornerRadius: Kairo.Radius.xl, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Kairo.Radius.xl, style: .continuous)
                        .fill(Kairo.Palette.glassTint)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Kairo.Radius.xl, style: .continuous)
                        .strokeBorder(Kairo.Palette.glassStroke, lineWidth: 0.5)
                }
        }
        .kairoElevation(Kairo.Elevation.popover)
        .foregroundStyle(Kairo.Palette.text)
        .onAppear { bridge.start() }
    }

    // MARK: - Header (segmented tabs)

    private var header: some View {
        HStack(spacing: Kairo.Space.xs) {
            ForEach(Tab.allCases, id: \.self) { t in
                tabButton(t)
            }
            Spacer(minLength: 0)
        }
    }

    private func tabButton(_ t: Tab) -> some View {
        let isActive = tab == t
        return Button {
            withAnimation(Kairo.Motion.snappy) { tab = t }
        } label: {
            HStack(spacing: Kairo.Space.xs) {
                Image(systemName: t.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(t.label)
                    .font(isActive ? Kairo.Typography.captionStrong : Kairo.Typography.caption)
            }
            .foregroundStyle(isActive ? Kairo.Palette.text : Kairo.Palette.textDim)
            .padding(.horizontal, Kairo.Space.md)
            .padding(.vertical, Kairo.Space.sm)
            .background {
                if isActive {
                    Capsule(style: .continuous)
                        .fill(Kairo.Palette.surfaceHi)
                        .matchedGeometryEffect(id: "tabIndicator", in: tabIndicator)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        Group {
            switch tab {
            case .notifications: NotificationCenterView(bridge: bridge)
            case .home:          HomeControlView()
            case .cameras:       CameraWallView()
            }
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 4)),
            removal:   .opacity
        ))
    }
}
