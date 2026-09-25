//
//  SystemNotificationManager.swift
//  boringNotch
//
import AppKit
import Combine
import Defaults

struct SystemNotification: Identifiable, Equatable {
    let id: String
    let appName: String?
    let bundleID: String?
    let title: String?
    let subtitle: String?
    let body: String?
    let receivedAt: Date
}

@MainActor
final class SystemNotificationManager: ObservableObject {
    static let shared = SystemNotificationManager()

    @Published private(set) var activeNotification: SystemNotification?
    @Published private(set) var queuedNotifications: [SystemNotification] = []

    private let queueLimit = 5
    private let displayDuration: TimeInterval = 8
    private var dismissTask: Task<Void, Never>?
    private var notificationObserver: NSObjectProtocol?
    private var isUserPresent = false

    private init() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .systemNotificationDidAppear, object: nil, queue: .main
        ) { [weak self] note in
            guard let payload = note.userInfo as? [String: String] else { return }
            Task { @MainActor in self?.add(payload) }
        }
    }

    deinit {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    func start() async {
        guard await XPCHelperClient.shared.isAccessibilityAuthorized() else { return }
        updateFilter()
        _ = await XPCHelperClient.shared.startNotificationWatching()
    }

    func stop() {
        XPCHelperClient.shared.stopNotificationWatching()
        queuedNotifications.removeAll()
        isUserPresent = false
        dismissActive()
    }

    func holdActive() {
        isUserPresent = true
        dismissTask?.cancel()
        dismissTask = nil
    }

    func resumeDismiss(after delay: TimeInterval = 2) {
        isUserPresent = false
        queuedNotifications.removeAll()
        guard let notification = activeNotification else { return }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.dismissActive(token: notification.id)
        }
    }

    func dismissActive(token: String? = nil) {
        guard token == nil || activeNotification?.id == token else { return }
        dismissTask?.cancel()
        dismissTask = nil
        activeNotification = nil
        if isUserPresent {
            promoteNext()
        } else {
            queuedNotifications.removeAll()
        }
    }

    func showNextQueued() {
        guard isUserPresent, let next = queuedNotifications.first else { return }
        if let activeNotification {
            queuedNotifications.append(activeNotification)
        }
        queuedNotifications.removeFirst()
        show(next)
    }

    func open(_ notification: SystemNotification) async -> Bool {
        guard let bundleID = notification.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return false }
        return NSWorkspace.shared.open(url)
    }

    private func add(_ payload: [String: String]) {
        guard let token = payload["token"], !token.isEmpty else { return }
        let notification = SystemNotification(
            id: token,
            appName: nonEmpty(payload["appName"]),
            bundleID: nonEmpty(payload["bundleID"]),
            title: nonEmpty(payload["title"]),
            subtitle: nonEmpty(payload["subtitle"]),
            body: nonEmpty(payload["body"]),
            receivedAt: Date()
        )
        guard isAllowed(notification) else { return }
        guard activeNotification == nil else {
            guard isUserPresent else {
                show(notification)
                return
            }
            guard !queuedNotifications.contains(where: { $0.id == notification.id }) else { return }
            queuedNotifications.append(notification)
            if queuedNotifications.count > queueLimit {
                queuedNotifications.removeFirst()
            }
            return
        }
        show(notification)
    }

    private func show(_ notification: SystemNotification) {
        dismissTask?.cancel()
        activeNotification = notification
        scheduleDismiss(for: notification.id)
    }

    private func scheduleDismiss(for token: String) {
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.displayDuration ?? 8))
            guard !Task.isCancelled else { return }
            await self?.dismissActive(token: token)
        }
    }

    private func promoteNext() {
        guard activeNotification == nil, !queuedNotifications.isEmpty else { return }
        show(queuedNotifications.removeFirst())
    }

    func updateFilter() {
        XPCHelperClient.shared.setNotificationFilter(
            bundleIDs: Defaults[.notificationAllowedApps],
            allApps: Defaults[.notificationsFromAllApps]
        )
    }

    private func isAllowed(_ notification: SystemNotification) -> Bool {
        if Defaults[.notificationsFromAllApps] { return true }
        if let bundleID = notification.bundleID {
            return Defaults[.notificationAllowedApps].contains(bundleID)
        }
        guard let appName = notification.appName?.lowercased(), !appName.isEmpty else {
            return false
        }
        return Defaults[.notificationAllowedApps].contains { bundleID in
            bundleID.split(separator: ".").last.map {
                appName == $0.lowercased()
            } ?? false
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
