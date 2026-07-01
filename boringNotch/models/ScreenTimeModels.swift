//
//  ScreenTimeModels.swift
//  boringNotch
//
//  Pure, Foundation-only data model + accounting logic for the Screen Time widget.
//  Deliberately free of AppKit / SwiftUI / Defaults so it can be unit-tested with the
//  `swift` CLI. The AppKit/SwiftUI/Defaults wiring lives in ScreenTimeManager.
//

import Foundation

// MARK: - Category

/// A grouping for applications (Development, Social, …). `colorHex` is a "#RRGGBB"
/// string so this type stays free of SwiftUI/AppKit and remains Codable + testable.
struct AppCategory: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let colorHex: String

    init(id: String, name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

// MARK: - Usage

/// Accumulated foreground time for a single app within one logical day.
struct AppUsage: Codable, Hashable {
    let bundleID: String
    var displayName: String
    var seconds: TimeInterval
}

/// All usage for one logical day, keyed by the day's reset instant.
struct DailyUsage: Codable, Hashable {
    /// The reset instant that opens this logical day (see `ScreenTimeMath.dayStart`).
    let dayStart: Date
    var switchCount: Int
    /// bundleID -> usage
    var perApp: [String: AppUsage]

    init(dayStart: Date, switchCount: Int = 0, perApp: [String: AppUsage] = [:]) {
        self.dayStart = dayStart
        self.switchCount = switchCount
        self.perApp = perApp
    }

    var totalSeconds: TimeInterval {
        perApp.values.reduce(0) { $0 + $1.seconds }
    }

    /// Apps ranked by time, descending.
    var rankedApps: [AppUsage] {
        perApp.values.sorted { $0.seconds > $1.seconds }
    }
}

// MARK: - Store

/// The full rolling history. Keyed by `dayStart`. Codable so it can be persisted as a
/// blob by the manager.
struct UsageStore: Codable {
    var days: [Date: DailyUsage]

    init(days: [Date: DailyUsage] = [:]) {
        self.days = days
    }

    func daily(for dayStart: Date) -> DailyUsage? { days[dayStart] }

    /// Add `seconds` of foreground time for an app on a given logical day.
    mutating func add(seconds: TimeInterval, bundleID: String, displayName: String, on dayStart: Date) {
        guard seconds > 0 else { return }
        var day = days[dayStart] ?? DailyUsage(dayStart: dayStart)
        if var existing = day.perApp[bundleID] {
            existing.seconds += seconds
            // Keep the most recent non-empty display name.
            if !displayName.isEmpty { existing.displayName = displayName }
            day.perApp[bundleID] = existing
        } else {
            day.perApp[bundleID] = AppUsage(bundleID: bundleID, displayName: displayName, seconds: seconds)
        }
        days[dayStart] = day
    }

    /// Record a single app switch on a logical day.
    mutating func recordSwitch(on dayStart: Date) {
        var day = days[dayStart] ?? DailyUsage(dayStart: dayStart)
        day.switchCount += 1
        days[dayStart] = day
    }

    /// Remove days whose `dayStart` is older than `retentionDays` relative to `now`.
    mutating func prune(retentionDays: Int, now: Date, calendar: Calendar = .current) {
        guard retentionDays > 0 else { return }
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now) else { return }
        days = days.filter { $0.key >= cutoff }
    }
}

// MARK: - Math

/// Pure helpers for logical-day bucketing and segment attribution.
enum ScreenTimeMath {
    /// The most recent occurrence of `resetHour:resetMinute` at or before `date`.
    /// This instant is the key for the logical day that `date` belongs to.
    static func dayStart(for date: Date, resetHour: Int, resetMinute: Int, calendar: Calendar = .current) -> Date {
        let candidate = calendar.date(
            bySettingHour: max(0, min(23, resetHour)),
            minute: max(0, min(59, resetMinute)),
            second: 0,
            of: date
        ) ?? date
        if candidate <= date { return candidate }
        return calendar.date(byAdding: .day, value: -1, to: candidate) ?? candidate
    }

    /// Attribute a foreground segment [from, to] for one app into the store, splitting
    /// across logical-day boundaries so each day gets only its share.
    static func attribute(
        from: Date,
        to: Date,
        bundleID: String,
        displayName: String,
        into store: inout UsageStore,
        resetHour: Int,
        resetMinute: Int,
        calendar: Calendar = .current
    ) {
        guard to > from else { return }
        var cursor = from
        var guardCount = 0
        while cursor < to && guardCount < 4000 {
            guardCount += 1
            let dayStart = dayStart(for: cursor, resetHour: resetHour, resetMinute: resetMinute, calendar: calendar)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? to
            let segmentEnd = min(to, nextDay)
            store.add(
                seconds: segmentEnd.timeIntervalSince(cursor),
                bundleID: bundleID,
                displayName: displayName,
                on: dayStart
            )
            cursor = segmentEnd
        }
    }

    /// Aggregate a day's per-app usage into per-category totals, sorted descending.
    static func categoryTotals(
        for daily: DailyUsage,
        resolver: (String) -> AppCategory
    ) -> [(category: AppCategory, seconds: TimeInterval)] {
        var totals: [String: (AppCategory, TimeInterval)] = [:]
        for usage in daily.perApp.values {
            let cat = resolver(usage.bundleID)
            let current = totals[cat.id]?.1 ?? 0
            totals[cat.id] = (cat, current + usage.seconds)
        }
        return totals.values
            .map { (category: $0.0, seconds: $0.1) }
            .sorted { $0.seconds > $1.seconds }
    }
}
