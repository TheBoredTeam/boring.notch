import Foundation

enum DailyWorkflowKind: String, Codable, CaseIterable, Equatable {
    case morningPlanning
    case eveningReview
}

struct DailyWorkflowPreferences: Codable, Equatable {
    var morningPlanningEnabled: Bool
    var morningPlanningMinutes: Int
    var eveningReviewEnabled: Bool
    var eveningReviewMinutes: Int

    static let `default` = DailyWorkflowPreferences(
        morningPlanningEnabled: false,
        morningPlanningMinutes: 8 * 60,
        eveningReviewEnabled: false,
        eveningReviewMinutes: 20 * 60
    )

    func isEnabled(_ kind: DailyWorkflowKind) -> Bool {
        switch kind {
        case .morningPlanning: morningPlanningEnabled
        case .eveningReview: eveningReviewEnabled
        }
    }

    func minutesAfterMidnight(for kind: DailyWorkflowKind) -> Int {
        switch kind {
        case .morningPlanning: morningPlanningMinutes
        case .eveningReview: eveningReviewMinutes
        }
    }
}

struct DailyWorkflowDay: Codable, Equatable {
    let era: Int
    let year: Int
    let month: Int
    let day: Int

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        era = components.era ?? 1
        year = components.year ?? 0
        month = components.month ?? 0
        day = components.day ?? 0
    }
}

struct DailyWorkflowCompletionState: Codable, Equatable {
    private var morningPlanningDay: DailyWorkflowDay?
    private var eveningReviewDay: DailyWorkflowDay?

    init(
        morningPlanningDay: DailyWorkflowDay? = nil,
        eveningReviewDay: DailyWorkflowDay? = nil
    ) {
        self.morningPlanningDay = morningPlanningDay
        self.eveningReviewDay = eveningReviewDay
    }

    func isCompleted(_ kind: DailyWorkflowKind, on date: Date, calendar: Calendar) -> Bool {
        let expectedDay = DailyWorkflowDay(date: date, calendar: calendar)
        switch kind {
        case .morningPlanning: return morningPlanningDay == expectedDay
        case .eveningReview: return eveningReviewDay == expectedDay
        }
    }

    mutating func markCompleted(_ kind: DailyWorkflowKind, on date: Date, calendar: Calendar) {
        let completedDay = DailyWorkflowDay(date: date, calendar: calendar)
        switch kind {
        case .morningPlanning: morningPlanningDay = completedDay
        case .eveningReview: eveningReviewDay = completedDay
        }
    }
}

struct DailyReminderItem: Equatable, Identifiable {
    let id: String
    let title: String
    let dueDate: Date
    let isCompleted: Bool
    let listTitle: String
}

struct DailyReminderSections: Equatable {
    let all: [DailyReminderItem]
    let completed: [DailyReminderItem]
    let incomplete: [DailyReminderItem]

    init(items: [DailyReminderItem], sessionDate: Date, calendar: Calendar) {
        let day = calendar.dateInterval(of: .day, for: sessionDate)
        let filtered =
            items
            .filter { item in
                guard let day else { return false }
                return day.contains(item.dueDate)
            }
            .sorted {
                if $0.dueDate == $1.dueDate {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return $0.dueDate < $1.dueDate
            }

        all = filtered
        completed = filtered.filter(\.isCompleted)
        incomplete = filtered.filter { !$0.isCompleted }
    }
}

enum DailyWorkflowSchedule {
    static func dueWorkflow(
        at date: Date,
        preferences: DailyWorkflowPreferences,
        completionState: DailyWorkflowCompletionState,
        calendar: Calendar = .current
    ) -> DailyWorkflowKind? {
        for kind in DailyWorkflowKind.allCases where preferences.isEnabled(kind) {
            guard !completionState.isCompleted(kind, on: date, calendar: calendar) else {
                continue
            }
            guard
                let trigger = triggerDate(
                    for: kind, on: date, preferences: preferences, calendar: calendar)
            else {
                continue
            }
            if trigger <= date {
                return kind
            }
        }
        return nil
    }

    static func nextEvaluation(
        after date: Date,
        preferences: DailyWorkflowPreferences,
        completionState: DailyWorkflowCompletionState,
        calendar: Calendar = .current
    ) -> Date? {
        let candidates = DailyWorkflowKind.allCases.compactMap { kind -> Date? in
            guard preferences.isEnabled(kind) else { return nil }

            if !completionState.isCompleted(kind, on: date, calendar: calendar),
                let today = triggerDate(
                    for: kind, on: date, preferences: preferences, calendar: calendar),
                today > date
            {
                return today
            }

            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) else {
                return nil
            }
            return triggerDate(
                for: kind, on: tomorrow, preferences: preferences, calendar: calendar)
        }

        return candidates.min()
    }

    static func triggerDate(
        for kind: DailyWorkflowKind,
        on date: Date,
        preferences: DailyWorkflowPreferences,
        calendar: Calendar = .current
    ) -> Date? {
        let minutes = min(max(preferences.minutesAfterMidnight(for: kind), 0), 23 * 60 + 59)
        return calendar.date(
            byAdding: .minute,
            value: minutes,
            to: calendar.startOfDay(for: date)
        )
    }
}

final class DailyWorkflowPreferencesStore {
    private enum Key {
        static let preferences = "dailyWorkflow.preferences.v1"
        static let completionState = "dailyWorkflow.completionState.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadPreferences() -> DailyWorkflowPreferences {
        decode(DailyWorkflowPreferences.self, forKey: Key.preferences) ?? .default
    }

    func savePreferences(_ preferences: DailyWorkflowPreferences) throws {
        try encode(preferences, forKey: Key.preferences)
    }

    func loadCompletionState() -> DailyWorkflowCompletionState {
        decode(DailyWorkflowCompletionState.self, forKey: Key.completionState) ?? .init()
    }

    func saveCompletionState(_ state: DailyWorkflowCompletionState) throws {
        try encode(state, forKey: Key.completionState)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) throws {
        defaults.set(try encoder.encode(value), forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
