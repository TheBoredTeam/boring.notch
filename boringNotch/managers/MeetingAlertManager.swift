//
//  MeetingAlertManager.swift
//  boringNotch
//
//  Watches the calendar and publishes the meeting the notch should be
//  showing, if any.
//
//  All the judgement about *which* meeting lives in `MeetingAlertSelector`;
//  this class supplies the clock and the event list, and remembers what the
//  user dismissed.
//

import Combine
import Defaults
import Foundation
import SwiftUI

@MainActor
final class MeetingAlertManager: ObservableObject {
    static let shared = MeetingAlertManager()

    @Published private(set) var alert: MeetingAlert?

    /// Dismissals are per-run, not persisted: the point is "I've seen this,
    /// stop nagging me for the next few minutes", and a relaunch hours later
    /// should not still be suppressing a meeting.
    private var dismissedEventIDs: Set<String> = []

    private var tickTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        Defaults.publisher(.meetingLiveActivity)
            .sink { [weak self] change in
                Task { @MainActor in
                    if change.newValue { self?.start() } else { self?.stop() }
                }
            }
            .store(in: &cancellables)

        if Defaults[.meetingLiveActivity] {
            start()
        }
    }

    // MARK: - Lifecycle

    private func start() {
        guard tickTask == nil else { return }
        // Once a minute is enough: the alert is expressed in whole minutes, so
        // a faster tick would recompute the same string over and over. The
        // first evaluation is immediate so enabling the feature during a
        // meeting shows it at once rather than up to a minute later.
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.refresh() }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func stop() {
        tickTask?.cancel()
        tickTask = nil
        alert = nil
    }

    // MARK: - Evaluation

    private func refresh() {
        let next = MeetingAlertSelector.alert(
            from: CalendarManager.shared.events,
            now: .now,
            policy: MeetingAlertPolicy(
                leadTime: TimeInterval(Defaults[.meetingLeadTimeMinutes]) * 60,
                lingerAfterStart: TimeInterval(Defaults[.meetingLingerMinutes]) * 60,
                requiresMeetingLink: Defaults[.meetingRequiresJoinLink]
            ),
            dismissedEventIDs: dismissedEventIDs
        )

        // Housekeeping: forget dismissals for meetings that are no longer
        // anywhere near now, so the set cannot grow all day.
        if next == nil, !dismissedEventIDs.isEmpty {
            let live = Set(CalendarManager.shared.events.map(\.id))
            dismissedEventIDs.formIntersection(live)
        }

        guard next != alert else { return }
        withAnimation(.smooth) { alert = next }
    }

    // MARK: - Actions

    func dismissCurrent() {
        guard let alert else { return }
        dismissedEventIDs.insert(alert.eventID)
        withAnimation(.smooth) { self.alert = nil }
    }

    /// Opens the join link and dismisses the alert.
    ///
    /// Dismissing on join is what keeps the notch from still nagging about a
    /// meeting the user is now sitting in.
    func join() {
        guard let alert, let link = alert.meetingLink else { return }
        NSWorkspace.shared.open(link.url)
        dismissCurrent()
    }

    /// Opens the event in Calendar for anything that isn't a one-click join.
    func openInCalendar() {
        guard let alert,
              let event = CalendarManager.shared.events.first(where: { $0.id == alert.eventID }),
              let url = event.calendarAppURL()
        else { return }
        NSWorkspace.shared.open(url)
        dismissCurrent()
    }
}
