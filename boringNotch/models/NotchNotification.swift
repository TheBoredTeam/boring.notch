//
//  NotchNotification.swift
//  boringNotch
//
//  Created by tyler_song on 2025-12-08.
//

import Defaults
import Foundation

enum NotchNotificationCategory: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case battery
    case calendar
    case shelf
    case system
    case info

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .battery:
            return "bolt.fill"
        case .calendar:
            return "calendar"
        case .shelf:
            return "tray.full.fill"
        case .system:
            return "gearshape.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    var displayName: String {
        switch self {
        case .battery:
            return "Battery"
        case .calendar:
            return "Calendar"
        case .shelf:
            return "Shelf"
        case .system:
            return "System"
        case .info:
            return "Info"
        }
    }
}

struct NotchNotification: Identifiable, Codable, Hashable, Defaults.Serializable {
    let id: UUID
    let title: String
    let message: String
    let date: Date
    let category: NotchNotificationCategory
    var isRead: Bool

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        date: Date = Date(),
        category: NotchNotificationCategory,
        isRead: Bool = false
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.date = date
        self.category = category
        self.isRead = isRead
    }
}

