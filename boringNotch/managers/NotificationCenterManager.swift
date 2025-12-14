//
//  NotificationCenterManager.swift
//  boringNotch
//
//  Created by tyler_song on 2025-12-08.
//

import Combine
import Defaults
import Foundation
import UserNotifications

@MainActor
final class NotificationCenterManager: NSObject, ObservableObject {
    static let shared = NotificationCenterManager()

    @Published private(set) var notifications: [NotchNotification] = []
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()
    private let storageLimit = 200
    private var cancellables: Set<AnyCancellable> = []

    private override init() {
        super.init()
        loadStoredNotifications()
        pruneExpiredNotifications()
        refreshAuthorizationStatus()
        observeRetentionChanges()
    }

    func addNotification(
        title: String,
        message: String,
        category: NotchNotificationCategory,
        deliverToSystem: Bool = true
    ) {
        guard Defaults[.enableNotifications] else { return }
        guard isCategoryEnabled(category) else { return }

        let newNotification = NotchNotification(
            title: title,
            message: message,
            category: category
        )

        notifications.insert(newNotification, at: 0)
        trimToLimit()
        pruneExpiredNotifications()
        persist()

        guard shouldDeliverToSystem(deliverToSystem) else { return }
        sendSystemNotification(for: newNotification)
    }

    func markAsRead(_ id: UUID) {
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            notifications[index].isRead = true
            persist()
        }
    }

    func markAllRead() {
        notifications = notifications.map { item in
            var updated = item
            updated.isRead = true
            return updated
        }
        persist()
    }

    func clear() {
        notifications.removeAll()
        persist()
    }

    func refreshAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    func requestAuthorizationIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
            self?.refreshAuthorizationStatus()
        }
    }

    private func loadStoredNotifications() {
        notifications = Defaults[.storedNotifications]
            .sorted(by: { $0.date > $1.date })
    }

    private func persist() {
        Defaults[.storedNotifications] = notifications
    }

    private func trimToLimit() {
        if notifications.count > storageLimit {
            notifications = Array(notifications.prefix(storageLimit))
        }
    }

    private func pruneExpiredNotifications() {
        let days = Defaults[.notificationRetentionDays]
        let now = Date()
        let threshold = now.addingTimeInterval(TimeInterval(-days) * 24 * 60 * 60)
        notifications = notifications.filter { $0.date >= threshold }
    }

    private func shouldDeliverToSystem(_ requested: Bool) -> Bool {
        guard requested else { return false }
        guard Defaults[.notificationDeliveryStyle] == .banner else { return false }
        if Defaults[.respectDoNotDisturb], isFocusModeLikelyActive() {
            return false
        }
        return Defaults[.enableNotifications]
    }

    private func isCategoryEnabled(_ category: NotchNotificationCategory) -> Bool {
        switch category {
        case .battery:
            return Defaults[.showBatteryNotifications]
        case .calendar:
            return Defaults[.showCalendarNotifications]
        case .shelf:
            return Defaults[.showShelfNotifications]
        case .system:
            return Defaults[.showSystemNotifications]
        case .info:
            return Defaults[.showInfoNotifications]
        }
    }

    private func sendSystemNotification(for notification: NotchNotification) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }

            if settings.authorizationStatus == .notDetermined {
                self.requestAuthorizationIfNeeded()
            }

            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.message
            if Defaults[.notificationSoundEnabled] {
                content.sound = .default
            }
            content.categoryIdentifier = notification.category.rawValue

            let request = UNNotificationRequest(
                identifier: notification.id.uuidString,
                content: content,
                trigger: nil
            )

            self.center.add(request)
        }
    }

    private func isFocusModeLikelyActive() -> Bool {
        let domain = "com.apple.ncprefs" as CFString
        if let enabled = CFPreferencesCopyAppValue("dndEnabled" as CFString, domain) as? Bool {
            return enabled
        }
        return false
    }

    private func observeRetentionChanges() {
        Defaults.publisher(.notificationRetentionDays)
            .sink { [weak self] _ in
                guard let self else { return }
                self.pruneExpiredNotifications()
                self.persist()
            }
            .store(in: &cancellables)
    }
}

