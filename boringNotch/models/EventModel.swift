//
//  EventModel.swift
//  Calendr
//
//  Created by Paker on 24/12/20.
//  Original source: https://github.com/pakerwreah/Calendr
//  Modified by Alexander on 2025-05-18.
//

import AppKit
import Foundation

struct EventModel: Equatable, Identifiable {
    let id: String
    let start: Date
    let end: Date
    let title: String
    let location: String?
    let notes: String?
    let url: URL?
    let isAllDay: Bool
    let type: EventType
    let calendar: CalendarModel
    let participants: [Participant]
    let timeZone: TimeZone?
    let hasRecurrenceRules: Bool
    let priority: Priority?
}

enum AttendanceStatus: Comparable {
    case accepted
    case maybe
    case pending
    case declined
    case unknown

    private var comparisonValue: Int {
        switch self {
        case .accepted: return 1
        case .maybe: return 2
        case .declined: return 3
        case .pending: return 4
        case .unknown: return 5
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.comparisonValue < rhs.comparisonValue
    }
}

enum EventType: Equatable {
    case event(AttendanceStatus)
    case birthday
    case reminder(completed: Bool)
}

enum EventStatus: Equatable {
    case upcoming
    case inProgress
    case ended
}

extension EventType {
    var isEvent: Bool { if case .event = self { return true } else { return false } }
    var isBirthday: Bool { self ~= .birthday }
    var isReminder: Bool { if case .reminder = self { return true } else { return false } }
}

extension EventModel {
    
    var eventStatus: EventStatus {
        if start > Date() {
            return .upcoming
        } else if end > Date() {
            return .inProgress
        } else {
            return .ended
        }
    }
        
    var attendance: AttendanceStatus { if case .event(let attendance) = type { return attendance } else { return .unknown } }

    var isMeeting: Bool { !participants.isEmpty }

    func calendarAppURL() -> URL? {
        guard let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        guard !type.isReminder else {
            return URL(string: "x-apple-reminderkit://remcdreminder/\(encodedId)")
        }

        // Recurrence date fragment — only used by the Apple Calendar ical:// template.
        // Other app templates omit {date} so this replacement is a harmless no-op for them.
        let dateFragment: String
        if hasRecurrenceRules {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if !isAllDay {
                formatter.timeZone = .init(secondsFromGMT: 0)
            }
            guard let formattedDate = formatter.string(for: start) else { return nil }
            dateFragment = "/\(formattedDate)"
        } else {
            dateFragment = ""
        }

        if let template = Self.urlTemplate(forDefaultCalendarApp: ()) {
            let urlString = template
                .replacingOccurrences(of: "{id}", with: encodedId)
                .replacingOccurrences(of: "{date}", with: dateFragment)
            return URL(string: urlString)
        }

        // Fallback when the plist is missing or the default app has no entry.
        return URL(string: "ical://ekevent\(dateFragment)/\(encodedId)?method=show&options=more")
    }

    // Reads CalendarAppURLSchemes.plist and returns the URL template for the current
    // default calendar app (identified by which app handles webcal:// links).
    private static func urlTemplate(forDefaultCalendarApp _: ()) -> String? {
        guard
            let webcalURL = URL(string: "webcal://x"),
            let appURL = NSWorkspace.shared.urlForApplication(toOpen: webcalURL),
            let bundleId = Bundle(url: appURL)?.bundleIdentifier,
            let plistURL = Bundle.main.url(forResource: "CalendarAppURLSchemes", withExtension: "plist"),
            let data = try? Data(contentsOf: plistURL),
            let mapping = try? PropertyListDecoder().decode([String: String].self, from: data)
        else { return nil }

        return mapping[bundleId]
    }
}

struct Participant: Hashable {
    let name: String
    let status: AttendanceStatus
    let isOrganizer: Bool
    let isCurrentUser: Bool
}

enum Priority {
    case high
    case medium
    case low
}
