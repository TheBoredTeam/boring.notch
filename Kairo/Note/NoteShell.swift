import SwiftUI

struct NoteShell: View {
    @StateObject private var bridge = KairoNotificationBridge()
    @State private var tab: Tab = .notifications

    enum Tab: Hashable { case notifications, home, cameras }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Kairo.Palette.hairline)
            content
        }
        .background(
            RoundedRectangle(cornerRadius: Kairo.Radius.xl, style: .continuous)
                .fill(Kairo.Palette.background)
                .overlay(
                    RoundedRectangle(cornerRadius: Kairo.Radius.xl, style: .continuous)
                        .stroke(Kairo.Palette.hairline, lineWidth: 1)
                )
        )
        .foregroundColor(Kairo.Palette.text)
        .onAppear { bridge.start() }
    }

    private var header: some View {
        HStack {
            ForEach([Tab.notifications, .home, .cameras], id: \.self) { t in
                Button(action: { tab = t }) {
                    Text(label(for: t))
                        .font(.system(size: 12, weight: tab == t ? .semibold : .regular))
                        .foregroundColor(tab == t ? Kairo.Palette.text : Kairo.Palette.textDim)
                        .padding(.vertical, 14).padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func label(for t: Tab) -> String {
        switch t {
        case .notifications: return "Alerts"
        case .home:          return "Home"
        case .cameras:       return "Cameras"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .notifications: NotificationCenterView(bridge: bridge)
        case .home:          HomeControlView()
        case .cameras:       CameraWallView()
        }
    }
}
