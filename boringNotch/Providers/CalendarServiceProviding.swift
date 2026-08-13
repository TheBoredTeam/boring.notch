//
//  CalendarServiceProvider.swift
//  Calendr
//
//  Created by Paker on 31/12/20.
//  Original source: Original source: https://github.com/pakerwreah/Calendr
//  Modified by Alexander on 08/06/25
//

import Foundation
@preconcurrency import EventKit

@MainActor
protocol CalendarServiceProviding {
    func requestAccess(to type: EKEntityType) async throws -> Bool
    func calendars() async -> [CalendarModel]
    func events(from start: Date, to end: Date, calendars: [String]) async -> [EventModel]
    func createEvents(_ drafts: [CalendarEventDraft], preferredCalendarIDs: [String]) async throws -> [CreatedCalendarEvent]
}

@MainActor
final class CalendarService: CalendarServiceProviding {
    private let agentCalendarTitle = "蛋神"
    private let store = EKEventStore()
    
    func requestAccess(to type: EKEntityType) async throws -> Bool {
        if #available(macOS 14.0, *) {
            switch type {
            case .event:
                return try await store.requestFullAccessToEvents()
            case .reminder:
                return try await store.requestFullAccessToReminders()
            @unknown default:
                return false
            }
        } else {
            return try await store.requestAccess(to: type)
        }
    }
    
    private func hasAccess(to entityType: EKEntityType) -> Bool {
        let status = EKEventStore.authorizationStatus(for: entityType)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }
    
    func calendars() async -> [CalendarModel] {
        store.refreshSourcesIfNecessary()
        var calendars: [EKCalendar] = []
        
        for type in [EKEntityType.event, .reminder] where hasAccess(to: type) {
            calendars.append(contentsOf: store.calendars(for: type))
        }
        
        return calendars.map { CalendarModel(from: $0) }
    }
    
    func events(from start: Date, to end: Date, calendars ids: [String]) async -> [EventModel] {
        store.refreshSourcesIfNecessary()
        var events: [EventModel] = []
        
        // Fetch regular events
        if hasAccess(to: .event) {
            let eventCalendars = resolvedCalendars(for: .event, ids: ids)
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: eventCalendars)
            let ekEvents = store.events(matching: predicate)
            events.append(contentsOf: ekEvents.compactMap { EventModel(from: $0) })
        }
        
        // Fetch reminders
        if hasAccess(to: .reminder) {
            let reminderCalendars = resolvedCalendars(for: .reminder, ids: ids)
            events.append(contentsOf: await fetchReminders(from: start, to: end, calendars: reminderCalendars))
        }
        
        return events.sorted { $0.start < $1.start }
    }
    
    private func resolvedCalendars(for type: EKEntityType, ids: [String]) -> [EKCalendar]? {
        guard !ids.isEmpty else {
            return nil
        }

        return store.calendars(for: type).filter { ids.contains($0.calendarIdentifier) }
    }

    private func fetchReminders(from start: Date, to end: Date, calendars: [EKCalendar]?) async -> [EventModel] {
        return await withCheckedContinuation { continuation in
            // Create predicate for reminders with due dates in the specified range
            let predicate = store.predicateForReminders(in: calendars)
            
            store.fetchReminders(matching: predicate) { reminders in
                
                let filteredReminders = (reminders ?? []).filter { reminder in
                    // Check if reminder has a due date within our range
                    guard let dueDate = reminder.dueDateComponents?.date else {
                        return false
                    }
                    
                    return dueDate >= start && dueDate <= end
                }
                
                // Convert to EventModel
                let eventModels = filteredReminders.compactMap { reminder in
                    EventModel(from: reminder)
                }
                
                continuation.resume(returning: eventModels)
            }
        }
    }
    
    func setReminderCompleted(reminderID: String, completed: Bool) async {
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { return }
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
        } catch {
            print("Failed to update reminder completion: \(error)")
        }
    }

    func createEvents(_ drafts: [CalendarEventDraft], preferredCalendarIDs: [String]) async throws -> [CreatedCalendarEvent] {
        guard !drafts.isEmpty else {
            return []
        }

        guard hasAccess(to: .event) else {
            throw CalendarWriteError.accessDenied
        }

        guard let targetCalendar = try writableCalendar(preferredCalendarIDs: preferredCalendarIDs) else {
            throw CalendarWriteError.noWritableCalendar
        }

        var eventIdentifiers: [String] = []

        do {
            for draft in drafts {
                let normalizedEnd = max(draft.end, draft.start.addingTimeInterval(60 * 5))
                if let existing = matchingEvent(
                    title: draft.title,
                    start: draft.start,
                    end: normalizedEnd,
                    calendar: targetCalendar
                ) {
                    eventIdentifiers.append(existing.eventIdentifier)
                    continue
                }

                let event = EKEvent(eventStore: store)
                event.calendar = targetCalendar
                event.title = draft.title
                event.startDate = draft.start
                event.endDate = normalizedEnd
                event.notes = draft.notes
                event.location = draft.location
                if let alarmOffsetMinutes = draft.alarmOffsetMinutes {
                    event.addAlarm(EKAlarm(relativeOffset: TimeInterval(alarmOffsetMinutes * 60)))
                }

                try store.save(event, span: .thisEvent, commit: false)
                guard let identifier = event.eventIdentifier, !identifier.isEmpty else {
                    throw CalendarWriteError.verificationFailed
                }
                eventIdentifiers.append(identifier)
            }

            try store.commit()
        } catch {
            store.reset()
            throw error
        }

        store.refreshSourcesIfNecessary()
        return try eventIdentifiers.map { identifier in
            guard let persistedEvent = store.event(withIdentifier: identifier),
                  persistedEvent.calendar.title == agentCalendarTitle
            else {
                throw CalendarWriteError.verificationFailed
            }

            return CreatedCalendarEvent(
                identifier: persistedEvent.calendarItemIdentifier,
                title: persistedEvent.title ?? "AI 日程",
                start: persistedEvent.startDate,
                end: persistedEvent.endDate,
                calendarTitle: persistedEvent.calendar.title
            )
        }
    }

    #if DEBUG
    func removeEventsForRuntimeTest(calendarItemIdentifiers: [String]) throws -> Int {
        var removedCount = 0

        for identifier in calendarItemIdentifiers {
            guard let event = store.calendarItem(withIdentifier: identifier) as? EKEvent else {
                continue
            }
            try store.remove(event, span: .thisEvent, commit: false)
            removedCount += 1
        }

        if removedCount > 0 {
            try store.commit()
            store.refreshSourcesIfNecessary()
        }
        return removedCount
    }
    #endif

    private func matchingEvent(
        title: String,
        start: Date,
        end: Date,
        calendar: EKCalendar
    ) -> EKEvent? {
        let tolerance: TimeInterval = 1
        let predicate = store.predicateForEvents(
            withStart: start.addingTimeInterval(-60),
            end: end.addingTimeInterval(60),
            calendars: [calendar]
        )

        return store.events(matching: predicate).first { event in
            event.title == title
                && abs(event.startDate.timeIntervalSince(start)) <= tolerance
                && abs(event.endDate.timeIntervalSince(end)) <= tolerance
        }
    }

    private func writableCalendar(preferredCalendarIDs: [String]) throws -> EKCalendar? {
        _ = preferredCalendarIDs
        let eventCalendars = store.calendars(for: .event).filter(\.allowsContentModifications)

        if let agentCalendar = eventCalendars.first(where: { $0.title == agentCalendarTitle }) {
            return agentCalendar
        }

        return try createAgentCalendarIfPossible()
    }

    private func createAgentCalendarIfPossible() throws -> EKCalendar? {
        for source in calendarCreationSources() {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = agentCalendarTitle
            calendar.source = source

            do {
                try store.saveCalendar(calendar, commit: true)
                return calendar
            } catch {
                continue
            }
        }

        return nil
    }

    private func calendarCreationSources() -> [EKSource] {
        var candidates: [EKSource] = []

        if let defaultSource = store.defaultCalendarForNewEvents?.source {
            candidates.append(defaultSource)
        }

        candidates.append(contentsOf: store.sources.filter { $0.sourceType == .local })
        candidates.append(contentsOf: store.sources.filter { $0.sourceType == .calDAV || $0.sourceType == .exchange })

        var unique: [EKSource] = []
        for source in candidates where !unique.contains(where: { $0.sourceIdentifier == source.sourceIdentifier }) {
            unique.append(source)
        }
        return unique
    }
}

struct CalendarEventDraft: Equatable {
    let title: String
    let start: Date
    let end: Date
    let notes: String?
    let location: String?
    let alarmOffsetMinutes: Int?
}

struct CreatedCalendarEvent: Equatable {
    let identifier: String
    let title: String
    let start: Date
    let end: Date
    let calendarTitle: String
}

enum CalendarWriteError: LocalizedError {
    case accessDenied
    case noWritableCalendar
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access is not available. Enable it in Settings > Calendar."
        case .noWritableCalendar:
            return "无法创建或找到可写入的“蛋神”日历。"
        case .verificationFailed:
            return "日程写入后未能从系统日历回读验证，请稍后重试。"
        }
    }
}

// MARK: - Model Extensions

extension CalendarModel {
    init(from calendar: EKCalendar) {
        self.init(
            id: calendar.calendarIdentifier,
            account: calendar.accountTitle,
            title: calendar.title,
            color: calendar.color,
            isSubscribed: calendar.isSubscribed || calendar.isDelegate,
            isReminder: calendar.allowedEntityTypes.contains(.reminder)
        )
    }
}

extension EventModel {
    init?(from event: EKEvent) {
        guard let calendar = event.calendar else { return nil }
        
        self.init(
            id: event.calendarItemIdentifier,
            start: event.startDate,
            end: event.endDate,
            title: event.title ?? "",
            location: event.location,
            notes: event.notes,
            url: event.url,
            isAllDay: event.shouldBeAllDay,
            type: .init(from: event),
            calendar: .init(from: calendar),
            participants: .init(from: event),
            timeZone: calendar.isSubscribed || calendar.isDelegate ? nil : event.timeZone,
            hasRecurrenceRules: event.hasRecurrenceRules || event.isDetached,
            priority: nil
        )
    }
    
    init?(from reminder: EKReminder) {
        guard let calendar = reminder.calendar,
              let dueDateComponents = reminder.dueDateComponents,
              let date = Calendar.current.date(from: dueDateComponents)
        else { return nil }
        
        self.init(
            id: reminder.calendarItemIdentifier,
            start: date,
            end: Calendar.current.endOfDay(for: date),
            title: reminder.title ?? "",
            location: reminder.location,
            notes: reminder.notes,
            url: reminder.url,
            isAllDay: dueDateComponents.hour == nil,
            type: .reminder(completed: reminder.isCompleted),
            calendar: .init(from: calendar),
            participants: [],
            timeZone: calendar.isSubscribed || calendar.isDelegate ? nil : reminder.timeZone,
            hasRecurrenceRules: reminder.hasRecurrenceRules,
            priority: .init(from: reminder.priority)
        )
    }
}

extension EventType {
    init(from event: EKEvent) {
        self = event.birthdayContactIdentifier != nil ? .birthday : .event(.init(from: event.currentUser?.participantStatus))
    }
}

extension AttendanceStatus {
    init(from status: EKParticipantStatus?) {
        switch status {
        case .accepted:
            self = .accepted
        case .tentative:
            self = .maybe
        case .declined:
            self = .declined
        case .pending:
            self = .pending
        default:
            self = .unknown
        }
    }
}

extension Array where Element == Participant {
    init(from event: EKEvent) {
        var participants = event.attendees ?? []
        if let organizer = event.organizer, !participants.contains(where: { $0.url == organizer.url }) {
            participants.append(organizer)
        }
        self.init(
            participants.map { .init(from: $0, isOrganizer: $0.url == event.organizer?.url) }
        )
    }
}

extension Participant {
    init(from participant: EKParticipant, isOrganizer: Bool) {
        self.init(
            name: participant.name ?? participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
            status: .init(from: participant.participantStatus),
            isOrganizer: isOrganizer,
            isCurrentUser: participant.isCurrentUser
        )
    }
}

extension Priority {
    init?(from p: Int) {
        switch p {
        case 1...4:
            self = .high
        case 5:
            self = .medium
        case 6...9:
            self = .low
        default:
            return nil
        }
    }
}

// MARK: - Helper Extensions

private extension EKCalendar {
    var accountTitle: String {
        switch source.sourceType {
        case .local, .subscribed, .birthdays:
            return "Other"
        default:
            return source.title
        }
    }
    
    var isDelegate: Bool {
        if #available(macOS 13.0, *) {
            return source.isDelegate
        } else {
            return false
        }
    }
}

private extension EKEvent {
    var currentUser: EKParticipant? {
        attendees?.first(where: \.isCurrentUser)
    }
    
    var shouldBeAllDay: Bool {
        guard !isAllDay else { return true }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: startDate)
        let endOfDay = calendar.dateInterval(of: .day, for: endDate)?.end
        return startDate == startOfDay && endDate == endOfDay
    }
}

private extension Calendar {
    func endOfDay(for date: Date) -> Date {
        dateInterval(of: .day, for: date)?.end ?? date
    }
}
