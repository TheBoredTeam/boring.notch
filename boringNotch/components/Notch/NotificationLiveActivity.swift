//
//  NotificationLiveActivity.swift
//  boringNotch
//
//  Closed-state and expanded presentations for an incoming system
//  notification mirrored from Notification Center.
//
//  Design intent: mirror the restraint of a native macOS/iOS notification
//  banner — clear hierarchy (who → what → action), one obvious primary
//  action, generous but not wasteful spacing, and motion that settles
//  rather than bounces. Reuses the app's existing visual language (accent
//  color, AppIcon, MarqueeText, HoverButton) rather than inventing new
//  primitives.
//

import Defaults
import SwiftUI

/// Closed notch: app icon on the left, a status dot on the right that
/// briefly pulses on arrival — the same "something just happened" language
/// as an unread badge, without needing to read anything at a glance.
struct NotificationLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    let notification: SystemNotification

    // The ring is always in the tree; its scale/opacity are what animate.
    // Gating the view itself with `if` would give SwiftUI no starting frame
    // to interpolate from, so the "pulse" would just appear already faded.
    @State private var ringScale: CGFloat = 1
    @State private var ringOpacity: Double = 0

    private var itemSize: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    var body: some View {
        Group {
            if let code = notification.detectedCode {
                codePill(code)
            } else {
                statusPill
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .onAppear { pulse() }
        .onChange(of: notification.id) { _, _ in pulse() }
    }

    /// The default closed treatment: icon left, status dot right.
    private var statusPill: some View {
        HStack {
            NotificationAppIcon(bundleID: notification.bundleID, size: itemSize)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            ZStack {
                Circle()
                    .stroke(Color.effectiveAccent, lineWidth: 1.5)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                Circle()
                    .fill(notification.isLive ? Color.effectiveAccent : Color.secondary)
                    .frame(width: 7, height: 7)
            }
            .frame(width: itemSize, height: itemSize)
        }
    }

    /// A verification code doesn't need opening the notch to be useful — the
    /// closed pill widens just enough to show the code and a one-tap copy,
    /// same instinct as iOS surfacing OTPs directly on the lock screen.
    private func codePill(_ code: String) -> some View {
        HStack {
            NotificationAppIcon(bundleID: notification.bundleID, size: itemSize)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            HStack(spacing: 8) {
                Text(code)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                CodeCopyButton(code: code, diameter: itemSize)
            }
        }
    }

    private func pulse() {
        ringScale = 1
        ringOpacity = 0.8
        withAnimation(.easeOut(duration: 0.6)) {
            ringScale = 1.8
            ringOpacity = 0
        }
    }
}

/// Open notch: sender, message, and one clear primary action — a reply
/// composer, call controls, or a hand-off to the source app, depending on
/// what the notification actually supports.
struct NotificationExpandedView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var manager = SystemNotificationManager.shared

    let notification: SystemNotification

    @State private var replyText = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var didHandOff = false
    @FocusState private var replyFocused: Bool
    @State private var hostWindow: BoringNotchSkyLightWindow?
    @State private var suggestions: [String] = []
    @State private var isComposing = false

    private var kind: NotificationKind { .init(notification) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            headerAvatar

            // maxWidth (not .infinity) lets this shrink to whatever the
            // message actually needs while still wrapping long ones, so the
            // notch hugs the content instead of always spanning its full
            // width.
            VStack(alignment: .leading, spacing: 5) {
                header
                textBlock
                actionArea
            }
            .frame(maxWidth: 300, alignment: .leading)
        }
        .padding(.horizontal, 4)
        // Pinned to the card's actual top-right corner rather than sitting
        // inline at the avatar's vertical center, matching where a close
        // control belongs on a notification.
        .overlay(alignment: .topTrailing) {
            dismissButton
                .padding(.top, -2)
        }
        // Rebuild cleanly when one notification replaces another, instead of
        // reusing the previous one's view state.
        .id(notification.id)
        .background(WindowAccessor { self.hostWindow = $0 as? BoringNotchSkyLightWindow })
        // This view exists only while the notch is open, so appear/disappear
        // is the open/close signal: pause the countdown while the user is
        // looking at it, resume when they close. holdActive caps itself at
        // maxLifetime, so an abandoned open notch still lets the
        // notification go rather than pinning it forever.
        .onAppear {
            manager.holdActive()
            if kind == .reply { replyFocused = true }
        }
        .onDisappear {
            manager.resumeDismiss()
            // Always hand key status back — if this fired without the
            // focus-lost branch below running first (the whole view can
            // disappear while still focused, e.g. the notch closing), a
            // stuck `true` here would leave the window able to steal focus
            // on some later, unrelated click.
            hostWindow?.wantsKeyForTextInput = false
            // Same reasoning for the compose hold: a leaked one would pin
            // the notch open permanently, since every close path checks it.
            endComposing()
        }
        .onChange(of: replyFocused) { _, focused in
            // The window can only accept keystrokes while it's key, and it
            // must not stay key a moment longer than the field is actually
            // focused — see BoringNotchSkyLightWindow.wantsKeyForTextInput.
            hostWindow?.wantsKeyForTextInput = focused
            if focused {
                manager.holdWhileTyping()
                // Clicking into the field changes window key status, which
                // rebuilds tracking areas and fires a spurious hover-exit —
                // that's what was closing the notch the instant you tapped
                // the input. Every close path already honours
                // preventNotchClose, so hold it for the whole compose
                // session rather than trying to filter the bogus hover.
                beginComposing()
            } else {
                manager.holdActive()
                endComposing()
            }
        }
        .onChange(of: replyText) { _, _ in
            // Stop the timer's clock is exactly what typing should do — a
            // keystroke is the clearest possible "still here" signal, so it
            // gets an uncapped hold rather than the notch-open cap.
            if replyFocused { manager.holdWhileTyping() }
        }
    }

    // MARK: - Avatar

    /// A contact photo (or monogram fallback) when the notification has a
    /// human sender, badged with the source app's icon bottom-trailing —
    /// mirrors iMessage's own Communication Notifications treatment, but
    /// works for any app since it's a plain name lookup rather than an
    /// intent donation.
    ///
    /// Only attempted for messaging/calling apps. Other apps' "title" field
    /// is often not a person at all — Claude's is a session name, for
    /// instance — and treating it as one would both look wrong and fire a
    /// pointless Contacts search.
    private static let personAvatarBundleIDs: Set<String> = [
        "com.apple.MobileSMS", "com.apple.FaceTime", "com.apple.mail", "com.microsoft.Outlook",
        "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "com.tdesktop.Telegram",
        "com.hnc.Discord"
    ]

    @ViewBuilder
    private var headerAvatar: some View {
        if let sender = notification.sender,
           let bundleID = notification.bundleID,
           Self.personAvatarBundleIDs.contains(bundleID) {
            ZStack(alignment: .bottomTrailing) {
                PersonAvatarView(name: sender, size: 46)
                AppIcon(for: bundleID)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.black, lineWidth: 1.5))
                    .offset(x: 3, y: 3)
            }
        } else {
            NotificationAppIcon(bundleID: notification.bundleID, size: 46)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(notification.sender ?? notification.appName ?? "Notification")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            // No Spacer here — it would expand to fill and drag the notch
            // out to full width regardless of how short the message is.
            Text(notification.receivedAt, style: .relative)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        // Clears the close button, which overlays the card rather than
        // taking a layout slot — reserved here, on the one row it can
        // actually collide with, instead of on the whole card (which pushed
        // the reply row's right edge in by 20pt of dead space for no
        // reason, since nothing else in the card runs that wide).
        .padding(.trailing, 22)
    }

    /// Deliberately not HoverButton's default 30pt sizing — that reads as a
    /// full toolbar control; a notification's close button wants to be
    /// closer to iOS's compact circular dismiss.
    private var dismissButton: some View {
        Button {
            manager.dismissActive(token: notification.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(ScaleDownButtonStyle())
    }

    // MARK: - Body text

    @ViewBuilder
    private var textBlock: some View {
        if let subtitle = notification.subtitle, subtitle != notification.sender {
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        if let body = notification.body {
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(.secondary.opacity(0.9))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(1)
        }
    }

    // MARK: - Primary action, chosen by what the notification supports

    @ViewBuilder
    private var actionArea: some View {
        switch kind {
        case .code(let value):
            codeRow(value)
        case .call:
            callActionRow
        case .reply:
            replyRow
        case .openOnly:
            openRow
        }
    }

    // MARK: - Verification code

    private func codeRow(_ code: String) -> some View {
        HStack(spacing: 10) {
            Text(code)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .kerning(2)
                .foregroundStyle(.white)
                .lineLimit(1)

            CodeCopyButton(code: code, diameter: 26, showsLabel: true)
        }
        .padding(.top, 4)
    }

    // MARK: - Reply

    private var replyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !suggestions.isEmpty {
                suggestionChips
            }
            replyField
        }
        .task(id: notification.id) {
            guard Defaults[.smartRepliesEnabled], let body = notification.body else { return }
            suggestions = await SmartReplyManager.suggestReplies(sender: notification.sender, body: body)
        }
    }

    /// Tapping a chip fills the field rather than sending immediately — an
    /// AI-drafted reply should get a glance before it goes out under your
    /// name, not fire on a single tap.
    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        replyText = suggestion
                        replyFocused = true
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(ScaleDownButtonStyle())
                }
            }
        }
    }

    private var replyField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("Reply", text: $replyText, axis: .horizontal)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($replyFocused)
                    .onSubmit(send)
                    .disabled(isSending || didSend || didHandOff)
                    // Safe to let this fill available width now: the
                    // containing column is already capped at 300pt, so this
                    // only fills up to that cap rather than stretching the
                    // notch itself the way an unbounded TextField would.
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(replyFocused ? 0.18 : 0)))
            .animation(.easeOut(duration: 0.15), value: replyFocused)
            .frame(maxWidth: .infinity)

            sendButton
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var sendButton: some View {
        ZStack {
            Circle()
                .fill(fillStyle)
                .frame(width: 26, height: 26)

            if isSending {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else if didSend {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            } else if didHandOff {
                // Clipboard, not a checkmark: the message wasn't delivered,
                // it was copied for the user to paste into the app.
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canSend ? .white : .secondary)
            }
        }
        .animation(.smooth(duration: 0.25), value: isSending)
        .animation(.smooth(duration: 0.25), value: didSend)
        .animation(.smooth(duration: 0.25), value: didHandOff)
        .contentShape(Circle())
        .onTapGesture(perform: send)
        .disabled(!canSend)
        .sensoryFeedback(.success, trigger: didSend)
    }

    private var fillStyle: Color {
        if didSend { return .green }
        if didHandOff { return .orange }
        return canSend ? .effectiveAccent : .white.opacity(0.1)
    }

    private var canSend: Bool {
        !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending && !didSend && !didHandOff
    }

    /// SharingStateManager refcounts its sessions, so these must stay
    /// balanced — a leaked begin pins the notch open for good, since every
    /// close path honours preventNotchClose. The local flag guarantees at
    /// most one outstanding session per view regardless of how many times
    /// focus flips.
    private func beginComposing() {
        guard !isComposing else { return }
        isComposing = true
        SharingStateManager.shared.beginInteraction()
    }

    private func endComposing() {
        guard isComposing else { return }
        isComposing = false
        SharingStateManager.shared.endInteraction()
    }

    private func send() {
        guard canSend else { return }
        let text = replyText
        isSending = true
        Task {
            let outcome = await manager.reply(to: notification, text: text)
            isSending = false
            replyText = ""
            // A hand-off is not a delivery — showing the same checkmark for
            // both would tell the user their message went out when it's
            // actually sitting on the clipboard.
            didSend = outcome == .sent
            didHandOff = outcome == .handedOffToApp
            try? await Task.sleep(for: .milliseconds(1200))
            manager.dismissActive(token: notification.id)
        }
    }

    // MARK: - Calls

    /// Real phone/FaceTime affordance — green to accept, red to decline —
    /// rather than generic rectangular buttons.
    private var callActionRow: some View {
        HStack(spacing: 14) {
            if let decline = notification.actions.first(where: {
                $0.localizedCaseInsensitiveContains("decline")
            }) {
                callButton(symbol: "phone.down.fill", tint: .red) {
                    Task {
                        await manager.perform(decline, on: notification)
                        manager.dismissActive(token: notification.id)
                    }
                }
            }
            if let accept = notification.actions.first(where: { action in
                ["accept", "answer", "join"].contains { action.localizedCaseInsensitiveContains($0) }
            }) {
                callButton(symbol: "phone.fill", tint: .green) {
                    Task {
                        await manager.perform(accept, on: notification)
                        manager.dismissActive(token: notification.id)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func callButton(symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(tint)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
        .buttonStyle(ScaleDownButtonStyle())
    }

    // MARK: - Fallback: no reply field available

    private var openRow: some View {
        Button {
            Task { await manager.open(notification) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 11))
                Text("Open in \(notification.appName ?? "app")")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(ScaleDownButtonStyle())
        .padding(.top, 2)
    }
}

/// What a notification's actions actually let the user do — decides which
/// action row renders. Computed once per render rather than scattering the
/// same string matching across the view.
private enum NotificationKind: Equatable {
    case code(String), call, reply, openOnly

    init(_ notification: SystemNotification) {
        // A verification code wins over everything else — copying it is
        // almost certainly what the user opened the notch for.
        if let code = notification.detectedCode {
            self = .code(code)
            return
        }
        let hasCallActions = notification.actions.contains { action in
            ["accept", "decline", "answer", "join"].contains { action.localizedCaseInsensitiveContains($0) }
        }
        if hasCallActions {
            self = .call
        } else if notification.canReply {
            self = .reply
        } else {
            self = .openOnly
        }
    }
}

private struct NotificationAppIcon: View {
    let bundleID: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let bundleID {
                AppIcon(for: bundleID)
                    .resizable()
            } else {
                Image(systemName: "bell.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.22)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}

/// A restrained press state for the plain icon-style buttons above —
/// matches the subtle scale feedback used on the album art button rather
/// than a full opacity/highlight change.
private struct ScaleDownButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}

/// Copies a code to the pasteboard and morphs into a checkmark for a beat —
/// same confirmation language as the reply send button, so the two feel like
/// one design rather than two different affordances for "did that work?"
private struct CodeCopyButton: View {
    let code: String
    var diameter: CGFloat
    var showsLabel: Bool = false

    @State private var didCopy = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 4) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                if showsLabel {
                    Text(didCopy ? "Copied" : "Copy")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(.white)
            .frame(height: diameter)
            .padding(.horizontal, showsLabel ? 10 : 0)
            .frame(width: showsLabel ? nil : diameter)
            .background(
                (didCopy ? Color.green : Color.effectiveAccent),
                in: Capsule()
            )
        }
        .buttonStyle(ScaleDownButtonStyle())
        .animation(.smooth(duration: 0.25), value: didCopy)
        .sensoryFeedback(.success, trigger: didCopy)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }
}

/// Reads the NSWindow hosting this SwiftUI view. Needed because
/// BoringNotchSkyLightWindow can't become key by default (a click on the notch must
/// never steal focus from the frontmost app) — the reply field has to reach
/// through to that window to ask for key status only for the moment it's
/// actually being typed into.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
