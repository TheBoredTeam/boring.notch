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
    @FocusState private var replyFocused: Bool

    private var kind: NotificationKind { .init(notification) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            headerAvatar

            VStack(alignment: .leading, spacing: 5) {
                header
                textBlock
                actionArea
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Sized to its content, not to the notch. The opened notch is built
        // for the home/shelf tabs; a notification is a glance, so filling
        // that area just wraps two lines of text in empty black.
        .frame(maxWidth: 460, alignment: .leading)
        .padding(.horizontal, 4)
        // Rebuild cleanly when one notification replaces another, instead of
        // reusing the previous one's view state.
        .id(notification.id)
        // This view exists only while the notch is open, so appear/disappear
        // is the open/close signal: pause the countdown while the user is
        // looking at it, resume when they close. holdActive caps itself at
        // maxLifetime, so an abandoned open notch still lets the
        // notification go rather than pinning it forever.
        .onAppear {
            manager.holdActive()
            if kind == .reply { replyFocused = true }
        }
        .onDisappear { manager.resumeDismiss() }
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

            Text(notification.receivedAt, style: .relative)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize()

            Spacer(minLength: 8)

            HoverButton(icon: "xmark", iconColor: .secondary, scale: .medium) {
                manager.dismissActive(token: notification.id)
            }
        }
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

            Spacer(minLength: 8)

            CodeCopyButton(code: code, diameter: 26, showsLabel: true)
        }
        .padding(.top, 4)
    }

    // MARK: - Reply

    private var replyRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("Reply", text: $replyText, axis: .horizontal)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($replyFocused)
                    .onSubmit(send)
                    .disabled(isSending || didSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(replyFocused ? 0.18 : 0)))
            .animation(.easeOut(duration: 0.15), value: replyFocused)

            sendButton
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var sendButton: some View {
        ZStack {
            Circle()
                .fill(didSend ? Color.green : (canSend ? Color.effectiveAccent : Color.white.opacity(0.1)))
                .frame(width: 26, height: 26)

            if isSending {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else if didSend {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canSend ? .white : .secondary)
            }
        }
        .animation(.smooth(duration: 0.25), value: isSending)
        .animation(.smooth(duration: 0.25), value: didSend)
        .contentShape(Circle())
        .onTapGesture(perform: send)
        .disabled(!canSend)
        .sensoryFeedback(.success, trigger: didSend)
    }

    private var canSend: Bool {
        !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !didSend
    }

    private func send() {
        guard canSend else { return }
        let text = replyText
        isSending = true
        Task {
            let sent = await manager.reply(to: notification, text: text)
            isSending = false
            if sent {
                didSend = true
                replyText = ""
                try? await Task.sleep(for: .milliseconds(900))
                manager.dismissActive(token: notification.id)
            }
        }
    }

    // MARK: - Calls

    /// Real phone/FaceTime affordance — green to accept, red to decline —
    /// rather than generic rectangular buttons.
    private var callActionRow: some View {
        HStack(spacing: 14) {
            Spacer()
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
