import AppKit
import SwiftUI

struct CodexResponseDetailView: View {
    let notification: CodexJobNotification
    let maximumHeight: CGFloat
    let onHeightChange: (CGFloat) -> Void
    let onKeyboardFocusChange: (Bool) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var manager = CodexNotificationManager.shared

    var body: some View {
        if let preview = notification.responsePreview {
            CodexResponseCard(
                source: preview.source, isTruncated: preview.isTruncated,
                projectName: notification.projectName, chatTitle: notification.chatTitle,
                launchError: manager.compactLaunchError(for: notification),
                maximumHeight: maximumHeight, onHeightChange: onHeightChange,
                onOpenCodex: { manager.selectCompactActivity(for: notification) }
            )
            .background(CodexResponseKeyboardWindow())
            .onKeyPress { _ in
                onKeyboardFocusChange(true)
                return .ignored
            }
            .simultaneousGesture(TapGesture().onEnded { onKeyboardFocusChange(false) })
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
                if (note.object as? BoringNotchSkyLightWindow)?.allowsResponseKeyboardFocus == true {
                    onKeyboardFocusChange(false)
                }
            }
            .onDisappear { onKeyboardFocusChange(false) }
            .onExitCommand(perform: onDismiss)
        }
    }
}
/// Allows keyboard input only while this window is presenting a response.
private struct CodexResponseKeyboardWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ nsView: Anchor, context: Context) {}
    static func dismantleNSView(_ nsView: Anchor, coordinator: ()) {
        nsView.responseWindow?.allowsResponseKeyboardFocus = false
        if nsView.responseWindow?.isKeyWindow == true {
            nsView.responseWindow?.resignKey()
        }
    }

    final class Anchor: NSView {
        weak var responseWindow: BoringNotchSkyLightWindow?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            responseWindow?.allowsResponseKeyboardFocus = false
            responseWindow = window as? BoringNotchSkyLightWindow
            responseWindow?.allowsResponseKeyboardFocus = true
        }
    }
}
