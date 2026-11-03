import AppKit
import SwiftUI

struct CodexResponseDetailView: View {
    let notification: CodexJobNotification
    let maximumHeight: CGFloat
    let onHeightChange: (CGFloat) -> Void
    let onKeyboardFocusChange: (Bool) -> Void
    let onInteraction: () -> Void
    let onDismiss: () -> Void

    @ObservedObject private var manager = CodexNotificationManager.shared

    var body: some View {
        if let preview = notification.responsePreview {
            CodexResponseCard(
                source: preview.source, isTruncated: preview.isTruncated,
                projectName: notification.projectName, chatTitle: notification.chatTitle,
                launchError: manager.compactLaunchError(for: notification),
                maximumHeight: maximumHeight, onHeightChange: onHeightChange,
                onOpenCodex: { manager.selectCompactActivity(for: notification) },
                composer: AnyView(replyComposer)
            )
            .background(CodexResponseKeyboardWindow())
            .onKeyPress { _ in
                onKeyboardFocusChange(true)
                onInteraction()
                return .ignored
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
                if (note.object as? BoringNotchSkyLightWindow)?.allowsResponseKeyboardFocus == true {
                    onKeyboardFocusChange(false)
                }
            }
            .onDisappear { onKeyboardFocusChange(false) }
            .onExitCommand(perform: onDismiss)
        }
    }

    private var replyComposer: some View {
        let draft = manager.replyState.drafts[notification.sessionID]
        let delivery = draft?.delivery ?? .editing
        let editable = delivery.allowsEditing
        let sending: Bool = { if case .sending = delivery { return true }; return false }()
        let acknowledgement: String? = switch delivery {
        case .queued: "Reply received by Codex."
        case .queuedNeedsOpen: "Reply received by Codex. Open in Codex if the chat does not respond."
        default: nil
        }
        return VStack(alignment: .leading, spacing: 5) {
            CodexReplyComposer(
                text: Binding(
                    get: { manager.replyState.drafts[notification.sessionID]?.text ?? "" },
                    set: { manager.editReply($0, for: notification) }
                ),
                chatTitle: notification.chatTitle, canSend: draft?.canSend == true,
                isEditable: editable, isSending: sending, acknowledgement: acknowledgement,
                onSend: { manager.sendReply(for: notification) },
                onDismiss: onDismiss, onFocusChange: onKeyboardFocusChange,
                onInteraction: onInteraction
            )
            if let message = manager.replyMessage(for: notification) {
                HStack(spacing: 8) {
                    Text(message)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(delivery == .failed || delivery == .uncertain ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                    Spacer(minLength: 0)
                    if delivery == .failed {
                        Button("Retry") { manager.sendReply(for: notification) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    if delivery == .uncertain {
                        Button("Discard draft") { manager.discardReply(for: notification) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
            }
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
