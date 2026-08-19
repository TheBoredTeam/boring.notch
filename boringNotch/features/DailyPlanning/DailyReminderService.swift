import EventKit
import Foundation

enum DailyReminderAuthorization {
    case notDetermined
    case authorized
    case denied
}

@MainActor
protocol DailyReminderProviding {
    var authorization: DailyReminderAuthorization { get }
    var changeNotification: Notification.Name { get }

    func requestAccess() async throws -> Bool
    func reminders(from start: Date, to end: Date) async -> [DailyReminderItem]
    func setCompleted(_ completed: Bool, reminderID: String) async throws
}

/// Feature-local EventKit adapter. Keeping EventKit models behind this boundary prevents
/// daily planning from expanding the shared calendar service or depending on calendar UI models.
@MainActor
final class EventKitDailyReminderService: DailyReminderProviding {
    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    var authorization: DailyReminderAuthorization {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            return .notDetermined
        case .fullAccess, .authorized:
            return .authorized
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }

    var changeNotification: Notification.Name { .EKEventStoreChanged }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    func reminders(from start: Date, to end: Date) async -> [DailyReminderItem] {
        guard authorization == .authorized else { return [] }

        let predicate = store.predicateForReminders(in: store.calendars(for: .reminder))
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).compactMap { reminder -> DailyReminderItem? in
                    guard
                        let dueDate = self.dueDate(for: reminder),
                        dueDate >= start,
                        dueDate < end,
                        let calendar = reminder.calendar
                    else {
                        return nil
                    }

                    return DailyReminderItem(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        dueDate: dueDate,
                        isCompleted: reminder.isCompleted,
                        listTitle: calendar.title
                    )
                }
                continuation.resume(returning: items)
            }
        }
    }

    func setCompleted(_ completed: Bool, reminderID: String) async throws {
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw DailyReminderServiceError.reminderNotFound
        }

        reminder.isCompleted = completed
        try store.save(reminder, commit: true)
    }

    private func dueDate(for reminder: EKReminder) -> Date? {
        guard var components = reminder.dueDateComponents else { return nil }

        let isAllDay = components.hour == nil && components.minute == nil && components.second == nil
        var calendar = Calendar.current
        if isAllDay {
            calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = Calendar.current.timeZone
            components.timeZone = calendar.timeZone
            components.hour = 0
            components.minute = 0
            components.second = 0
        } else if components.timeZone == nil {
            components.timeZone = reminder.timeZone ?? calendar.timeZone
        }

        components.calendar = calendar
        return calendar.date(from: components)
    }
}

private enum DailyReminderServiceError: LocalizedError {
    case reminderNotFound

    var errorDescription: String? {
        "The reminder is no longer available."
    }
}
