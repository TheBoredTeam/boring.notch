//
//  CalendarLiveActivityViewModel.swift
//  boringNotch
//
//  Drives the closed-notch calendar live activity: a countdown ring to the
//  next event, then to the current event ending.
//

import Combine
import EventKit
import Foundation
import SwiftUI

@MainActor
final class CalendarLiveActivityViewModel: ObservableObject {
    static let shared = CalendarLiveActivityViewModel()

    /// How long before an event's start the activity begins showing.
    static let leadWindow: TimeInterval = 30 * 60

    @Published private(set) var activeEvent: EventModel?
    @Published private(set) var label: String = ""
    @Published private(set) var progress: Double = 0

    private var events: [EventModel] = []
    private var timer: Timer?
    private var eventStoreObserver: NSObjectProtocol?
    private var enabled = BoringViewCoordinator.shared.calendarLiveActivityEnabled

    private init() {
        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.reload() }
        }
        setEnabled(enabled)
    }

    deinit {
        if let eventStoreObserver { NotificationCenter.default.removeObserver(eventStoreObserver) }
        timer?.invalidate()
    }

    /// Called by the settings toggle to start/stop the activity.
    func setEnabled(_ on: Bool) {
        enabled = on
        timer?.invalidate()
        timer = nil
        guard on else {
            activeEvent = nil
            label = ""
            progress = 0
            return
        }
        // ponytail: 1-minute tick — minute-granularity countdown is enough.
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.tick() }
        }
        t.tolerance = 10
        timer = t
        Task { await reload() }
    }

    private func reload() async {
        guard enabled else { return }
        events = await CalendarManager.shared.todaysEvents()
        recompute(now: Date())
    }

    private func tick() async {
        recompute(now: Date())
        // If nothing is active, the day may have advanced past all cached
        // events; a cheap reload keeps us honest without an EventStore change.
        if activeEvent == nil { await reload() }
    }

    private func recompute(now: Date) {
        let result = Self.select(events: events, now: now, leadWindow: Self.leadWindow)
        activeEvent = result?.event
        label = result?.label ?? ""
        progress = result?.progress ?? 0
    }

    // MARK: - Pure logic (testable, no EventKit)

    struct Selection: Equatable {
        let event: EventModel
        let label: String
        let progress: Double
    }

    /// Picks the earliest event that is either in-progress or upcoming within
    /// `leadWindow`, skipping all-day events, and computes its countdown label
    /// and ring progress (1 = full, 0 = empty).
    static func select(events: [EventModel], now: Date, leadWindow: TimeInterval) -> Selection? {
        let candidates = events
            .filter { !$0.isAllDay }
            .filter { event in
                if event.end <= now { return false }                       // ended
                if event.start <= now { return true }                      // in progress
                return event.start.timeIntervalSince(now) <= leadWindow    // upcoming, in window
            }
            .sorted { $0.start < $1.start }

        guard let event = candidates.first else { return nil }

        let remaining: TimeInterval
        let total: TimeInterval
        let verb: String
        if event.start <= now {
            // In progress: drain over the event's duration.
            remaining = event.end.timeIntervalSince(now)
            total = max(event.end.timeIntervalSince(event.start), 1)
            verb = "ends in"
        } else {
            // Upcoming: drain over the lead window.
            remaining = event.start.timeIntervalSince(now)
            total = leadWindow
            verb = "in"
        }

        let progress = min(max(remaining / total, 0), 1)
        let label = "\(event.title) \(verb) \(shortDuration(remaining))"
        return Selection(event: event, label: label, progress: progress)
    }

    /// Rounds up to the nearest minute so "in 0m" never shows for a live event.
    static func shortDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int((interval / 60).rounded(.up)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}
