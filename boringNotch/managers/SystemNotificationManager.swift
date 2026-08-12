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

    /// Best-effort signal for showing the reply row. Notification Center
    /// doesn't label reply-capable banners consistently — WhatsApp exposes
    /// "Show Details" (reveals the field) and "Send" (submits), never the
    /// word "reply" (verified against a live banner). Either is a decent
    /// hint; `SystemNotificationManager.reply` is the actual source of truth
    /// and falls back to opening the app if no field materializes.
    var canReply: Bool {
        isLive && actions.contains {
            $0.localizedCaseInsensitiveContains("send") || $0.localizedCaseInsensitiveContains("details")
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

    /// How long the notch keeps showing a notification after it arrives.
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

        guard isAllowed(notification) else { return }
        show(notification)
        suppressSystemBannerIfNeeded(notification)
    }

    /// Closes the OS banner right after capture for apps the user has opted
    /// to mute at the system level — the notch's own live activity is meant
    /// to be the only thing they see for these. This can only run after the
    /// banner has already rendered and been read; nothing can stop it from
    /// appearing at all.
    private func suppressSystemBannerIfNeeded(_ notification: SystemNotification) {
        guard let bundleID = notification.bundleID,
              Defaults[.notificationSuppressedApps].contains(bundleID)
        else { return }
        Task { await XPCHelperClient.shared.dismissNotification(token: notification.id) }
    }

    /// The notch mirrors banners rather than replacing them, so an unfiltered
    /// feed would duplicate every system notification. Default to the messaging
    /// apps people actually reply to.
    private func isAllowed(_ notification: SystemNotification) -> Bool {
        if Defaults[.notificationsFromAllApps] { return true }
        guard let bundleID = notification.bundleID else { return false }
        return Defaults[.notificationAllowedApps].contains(bundleID)
    }

    private func show(_ notification: SystemNotification) {
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
        withAnimation(.smooth) { activeNotification = nil }
    }

    /// Keeps the notification up while the user is interacting with it.
    func holdActive() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    /// Restarts the dismiss countdown once the user stops interacting —
    /// without this a held notification would stay in the notch forever.
    func resumeDismiss(after delay: TimeInterval = 3) {
        guard let active = activeNotification, dismissTask == nil else { return }
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
        dismissActive()
    }

    // MARK: - Acting

    /// Sends an inline reply. Returns false when the banner is gone or the app
    /// has no reply action — callers should fall back to `open`.
    @discardableResult
    func reply(to notification: SystemNotification, text: String) async -> Bool {
        let sent = await XPCHelperClient.shared.replyToNotification(token: notification.id, text: text)
        if !sent { await open(notification) }
        dismissActive(token: notification.id)
        return sent
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
