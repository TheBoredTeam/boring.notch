//
//  SystemNotificationManager.swift
//  boringNotch
//
//  Collects Notification Center banners captured by the XPC helper and exposes
//  them to the UI. The helper does the Accessibility work; this side only
//  models what is currently on screen.
//

import AppKit
import Combine
import Defaults
import SwiftUI

struct SystemNotification: Identifiable, Equatable {
    /// Notification Center's own identifier for the banner, valid while it is
    /// on screen. Also the token the helper needs to act on it.
    let id: String
    let appName: String?
    let bundleID: String?
    let title: String?
    let subtitle: String?
    let body: String?
    let actions: [String]
    let receivedAt: Date

    /// True while the banner still exists, i.e. while replying can work.
    var isLive: Bool = true

    /// Best-effort signal for showing the reply row. A collapsed WhatsApp
    /// banner exposes "Reply" directly; once expanded that's replaced by
    /// "Show Details"/"Send" (verified against live banners in both states).
    /// Any of the three is a decent hint; `SystemNotificationManager.reply`
    /// is the actual source of truth and falls back to opening the app if no
    /// field materializes.
    /// Whether to offer a reply box at all — based on the app supporting
    /// replies, not on whether the banner is still alive. The compose box
    /// stays for as long as the notification is in the notch; if the banner
    /// has since died, `reply` degrades instead of the UI disappearing out
    /// from under a half-typed message.
    var canReply: Bool {
        actions.contains {
            $0.localizedCaseInsensitiveContains("reply")
                || $0.localizedCaseInsensitiveContains("send")
                || $0.localizedCaseInsensitiveContains("details")
        }
    }

    /// A verification code found in the notification text, if any. Computed
    /// rather than stored — it's cheap regex work and only ever read a
    /// handful of times per notification.
    var detectedCode: String? {
        OTPDetector.detect(in: [title, subtitle, body].compactMap { $0 }.joined(separator: " "))
    }

    var icon: NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Whoever the message is from — banners put the sender in the title.
    var sender: String? { title }
}

@MainActor
final class SystemNotificationManager: ObservableObject {
    static let shared = SystemNotificationManager()

    /// Most recent first, live banners before expired ones.
    @Published private(set) var notifications: [SystemNotification] = []
    @Published private(set) var isWatching = false

    /// The notification the notch is currently showing, if any.
    @Published var activeNotification: SystemNotification?

    /// Notifications that arrived while the user was mid-reply, held back
    /// rather than shown. Promoted one at a time once they're done.
    @Published private(set) var queued: [SystemNotification] = []

    /// Set by the reply UI while its field has focus. Newer notifications
    /// queue instead of replacing the active one during this — yanking a
    /// message out from under someone mid-sentence loses what they typed.
    var isComposingReply = false {
        didSet {
            guard oldValue, !isComposingReply else { return }
            // Finished composing and the notification is already gone (sent
            // or dismissed) — nothing will promote the queue, so do it here.
            if activeNotification == nil { promoteNextQueued() }
        }
    }

    /// Queued banners are all held alive off-screen, so this can't grow
    /// without bound — past a handful, the oldest are dropped and released.
    private let queueLimit = 5

    /// How long the closed notch shows a notification before handing the
    /// pill back to whatever was there before (usually music). Only applies
    /// while the notch is closed and unhovered — hovering or opening it
    /// holds the notification indefinitely.
    private let activeDuration: TimeInterval = 8
    private var dismissTask: Task<Void, Never>?

    /// Expired banners are kept around briefly so the notch can still show the
    /// last message after the banner itself has faded.
    private let historyLimit = 20

    private var observers: [NSObjectProtocol] = []

    private init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .systemNotificationDidAppear, object: nil, queue: .main
        ) { [weak self] note in
            guard let payload = note.userInfo as? [String: String] else { return }
            MainActor.assumeIsolated { self?.add(payload) }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .systemNotificationDidDisappear, object: nil, queue: .main
        ) { [weak self] note in
            guard let token = note.userInfo?["token"] as? String else { return }
            MainActor.assumeIsolated { self?.markExpired(token) }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Lifecycle

    func start() async {
        guard await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true) else {
            isWatching = false
            return
        }
        isWatching = await XPCHelperClient.shared.startNotificationWatching()
        // Ask up front so the first banner isn't blocked on a permission
        // prompt mid-render. Contacts access is optional — a denial just
        // means every avatar falls back to a monogram.
        await ContactAvatarManager.shared.requestAccessIfNeeded()
    }

    func stop() {
        XPCHelperClient.shared.stopNotificationWatching()
        isWatching = false
        releaseQueued()
    }

    /// Frees every queued notification's held banner. Anything still queued
    /// is holding a parked, off-screen window, so dropping the queue without
    /// this would strand them.
    private func releaseQueued() {
        for notification in queued {
            XPCHelperClient.shared.releaseNotification(token: notification.id)
        }
        queued.removeAll()
    }

    // MARK: - Incoming banners

    private func add(_ payload: [String: String]) {
        guard let token = payload["token"], !token.isEmpty else { return }
        func value(_ key: String) -> String? {
            let string = payload[key] ?? ""
            return string.isEmpty ? nil : string
        }

        let notification = SystemNotification(
            id: token,
            appName: value("appName"),
            bundleID: value("bundleID"),
            title: value("title"),
            subtitle: value("subtitle"),
            body: value("body"),
            actions: (value("actions") ?? "").components(separatedBy: "\n").filter { !$0.isEmpty },
            receivedAt: Date()
        )

        notifications.removeAll { $0.id == token }
        notifications.insert(notification, at: 0)
        if notifications.count > historyLimit {
            notifications.removeLast(notifications.count - historyLimit)
        }

        guard isAllowed(notification) else {
            NSLog("[boringNotch] filtered out: \(notification.appName ?? "-") bundle=\(notification.bundleID ?? "nil")")
            return
        }

        // Hold the banner either way: a queued notification still needs its
        // reply field alive for when it's promoted, and holding is what
        // keeps that possible past the banner's few seconds on screen.
        holdSystemBanner(notification)

        if isComposingReply, activeNotification != nil {
            enqueue(notification)
            return
        }

        show(notification)
    }

    private func enqueue(_ notification: SystemNotification) {
        queued.removeAll { $0.id == notification.id }
        queued.append(notification)

        // Oldest out first. Their held banners are released on the way, or
        // they'd stay parked off-screen with nothing left to free them.
        while queued.count > queueLimit {
            let dropped = queued.removeFirst()
            XPCHelperClient.shared.releaseNotification(token: dropped.id)
        }
    }

    /// Shows the oldest queued notification, if any. Oldest first so a burst
    /// is read in the order it arrived.
    private func promoteNextQueued() {
        guard !queued.isEmpty else { return }
        let next = queued.removeFirst()
        show(next)
    }

    /// Holds the system banner open for as long as the notch is showing the
    /// notification, so its reply field stays usable — an untouched banner
    /// dies in seconds, taking the only means of replying with it — and
    /// parks it off-screen for the duration.
    ///
    /// Hiding isn't optional here: holding works by re-triggering the
    /// banner's details toggle, which leaves it expanded with its own reply
    /// field visible and focused. Two text fields fighting over the same
    /// keystrokes is worse than no keep-alive, so the notch is the only
    /// surface on screen while it's held.
    private func holdSystemBanner(_ notification: SystemNotification) {
        XPCHelperClient.shared.holdNotification(token: notification.id)
    }

    /// The notch mirrors banners rather than replacing them, so an unfiltered
    /// feed would duplicate every system notification. Default to the messaging
    /// apps people actually reply to.
    private func isAllowed(_ notification: SystemNotification) -> Bool {
        if Defaults[.notificationsFromAllApps] { return true }

        if let bundleID = notification.bundleID {
            return Defaults[.notificationAllowedApps].contains(bundleID)
        }

        // Bundle ID resolution goes through the app's *running* name, which
        // can miss (renamed app, helper process owning the notification, an
        // app that quit between posting and capture). Rather than silently
        // dropping the notification, fall back to matching the app name
        // against the tail of an allowed bundle ID — "WhatsApp" against
        // net.whatsapp.WhatsApp.
        guard let appName = notification.appName?.lowercased(), !appName.isEmpty else { return false }
        return Defaults[.notificationAllowedApps].contains { bundleID in
            bundleID.split(separator: ".").last.map { appName == $0.lowercased() } ?? false
        }
    }

    private func show(_ notification: SystemNotification) {
        // A newer notification replaces the active one directly here rather
        // than going through dismissActive, so its hold was never being
        // released: dismissActive only releases whatever activeNotification
        // happens to be *when it runs*, and by the time a superseded
        // notification would be dismissed it's already been overwritten.
        // The result was a parked, off-screen banner window that never came
        // back — and since the same window can get reused by
        // notificationcenterui for its own real Notification Center panel,
        // that panel could end up opening off-screen too, which is why the
        // system clock stopped visibly doing anything.
        if let previous = activeNotification, previous.id != notification.id {
            XPCHelperClient.shared.releaseNotification(token: previous.id)
        }
        withAnimation(.smooth) { activeNotification = notification }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.activeDuration ?? 8))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.dismissActive(token: notification.id) }
        }
    }

    /// Passing a token only dismisses if it is still the one on screen, so a
    /// newer notification isn't cleared by an older one's timer.
    func dismissActive(token: String? = nil) {
        if let token, activeNotification?.id != token { return }
        dismissTask?.cancel()
        dismissTask = nil
        // Stop holding the system banner open — otherwise the keep-alive
        // would pin it (visibly, for non-hidden apps) long after the notch
        // has moved on.
        if let id = activeNotification?.id {
            XPCHelperClient.shared.releaseNotification(token: id)
        }
        withAnimation(.smooth) { activeNotification = nil }

        // Anything that queued up behind a reply gets its turn now. Skipped
        // while still composing — the reply field can be focused for a beat
        // after a send, and promoting there would replace the "sent"
        // confirmation before it's been seen.
        if !isComposingReply { promoteNextQueued() }
    }

    /// Keeps the notification up for as long as the reply field is being
    /// typed into. Same behaviour as `holdActive` now — kept as a separate
    /// name because the call sites mean different things.
    func holdWhileTyping() {
        holdActive()
    }

    /// Holds the notification indefinitely while the notch is open. No time
    /// cap: it stays until the notch closes or a newer notification
    /// replaces it.
    ///
    /// This previously capped at `maxLifetime` to stop an abandoned open
    /// notch pinning a stale message. That cap is unnecessary now that
    /// closing the notch clears the notification outright (see
    /// `resumeDismiss`) — the notch closing is what bounds it, so a stale
    /// one can't survive to be seen later regardless of how long it was
    /// held.
    func holdActive() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    /// Restarts the dismiss countdown once the user stops interacting —
    /// Clears the notification shortly after the notch closes. This is what
    /// bounds the otherwise-indefinite `holdActive`, so it must always
    /// schedule — a bail-if-busy check here would let an indefinite hold
    /// survive the notch closing and strand the notification.
    ///
    /// The short delay exists so briefly clipping the notch edge on the way
    /// past doesn't destroy a notification the user was mid-way through
    /// reading.
    func resumeDismiss(after delay: TimeInterval = 3) {
        guard let active = activeNotification else { return }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.dismissActive(token: active.id) }
        }
    }

    private func markExpired(_ token: String) {
        if let index = notifications.firstIndex(where: { $0.id == token }) {
            notifications[index].isLive = false
        }
        if activeNotification?.id == token {
            activeNotification?.isLive = false
        }
    }

    func clear() {
        notifications.removeAll()
        releaseQueued()
        dismissActive()
    }

    // MARK: - Acting

    enum ReplyOutcome {
        /// Delivered through the live banner's reply field.
        case sent
        /// The banner was gone, so the draft went to the clipboard and the
        /// app was opened for the user to paste.
        case handedOffToApp
    }

    /// Sends an inline reply.
    ///
    /// Replying types into the notification's own reply field via
    /// Accessibility, so it depends on that element still being reachable.
    /// The helper retains elements after their banner fades (the
    /// notification lives on in Notification Center), which is what makes
    /// replying work beyond the ~5s banner. If it genuinely can't be
    /// reached, hand off rather than dropping a typed message: the draft
    /// goes to the clipboard and the app opens so it's one paste away.
    @discardableResult
    func reply(to notification: SystemNotification, text: String) async -> ReplyOutcome {
        if await XPCHelperClient.shared.replyToNotification(token: notification.id, text: text) {
            NSLog("[boringNotch] reply sent via AX for \(notification.appName ?? "-")")
            playSentSound()
            dismissActive(token: notification.id)
            return .sent
        }

        // The banner is gone, so AX can't deliver. Messages is the one
        // supported app that can still be sent to properly — it has a real
        // scripting dictionary, so the reply goes out for real instead of
        // becoming a clipboard hand-off. Nothing equivalent exists for
        // WhatsApp/Telegram/Discord.
        if notification.bundleID == "com.apple.MobileSMS",
           let chatName = notification.sender,
           await XPCHelperClient.shared.sendIMessage(text, toChatNamed: chatName) {
            NSLog("[boringNotch] reply sent via Messages scripting for \(chatName)")
            playSentSound()
            dismissActive(token: notification.id)
            return .sent
        }

        NSLog("[boringNotch] reply could not be delivered (banner gone) — handing off to \(notification.appName ?? "app")")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        playHandOffSound()
        await open(notification)
        dismissActive(token: notification.id)
        return .handedOffToApp
    }

    /// Only on a real send. A "sent" sound when nothing was sent is a lie
    /// the user can't see through — they'd find out when the reply never
    /// arrived.
    private func playSentSound() {
        NSSound(named: "Tink")?.play()
    }

    /// Distinct from the sent sound on purpose: there's still feedback that
    /// the click registered, but it must not read as a delivery. The orange
    /// clipboard glyph on the button carries the actual meaning.
    private func playHandOffSound() {
        NSSound(named: "Pop")?.play()
    }

    func perform(_ action: String, on notification: SystemNotification) async -> Bool {
        await XPCHelperClient.shared.performNotificationAction(token: notification.id, name: action)
    }

    /// Opens the notification in its source app; falls back to launching the
    /// app once the banner is gone.
    @discardableResult
    func open(_ notification: SystemNotification) async -> Bool {
        if await XPCHelperClient.shared.openNotification(token: notification.id) { return true }
        guard let bundleID = notification.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return false }
        return (try? await NSWorkspace.shared.openApplication(at: url, configuration: .init())) != nil
    }

    func debugDump() async -> String {
        await XPCHelperClient.shared.notificationDebugDump()
    }
}
