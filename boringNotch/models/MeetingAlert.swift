//
//  MeetingAlert.swift
//  boringNotch
//
//  Decides which calendar event — if any — deserves the notch right now.
//
//  All the judgement lives here as pure functions over a supplied `Date`, so
//  "two minutes before a meeting I haven't declined, unless I dismissed it"
//  is testable without waiting for a real meeting or mutating a real calendar.
//

import Foundation

/// A meeting the notch is currently surfacing.
struct MeetingAlert: Equatable, Identifiable, Sendable {
    enum Timing: Equatable, Sendable {
        /// Starts in `seconds`.
        case startingSoon(seconds: TimeInterval)
        /// Already running, `seconds` in.
        case inProgress(seconds: TimeInterval)
    }

    let eventID: String
    let title: String
    let start: Date
    let end: Date
    let meetingLink: MeetingLink?
    let timing: Timing

    var id: String { eventID }

    var canJoin: Bool { meetingLink != nil }

    /// "in 2 min", "now", "12 min in".
    var localizedTiming: String {
        switch timing {
        case .startingSoon(let seconds):
            let minutes = Int((seconds / 60).rounded(.up))
            if minutes <= 0 {
                return NSLocalizedString("meeting_starting_now", comment: "A meeting that is starting right now")
            }
            return String(
                format: NSLocalizedString("meeting_starting_in", comment: "How long until a meeting starts, e.g. 'in 2 min'"),
                minutes
            )
        case .inProgress(let seconds):
            let minutes = Int(seconds / 60)
            if minutes <= 0 {
                return NSLocalizedString("meeting_starting_now", comment: "A meeting that is starting right now")
            }
            return String(
                format: NSLocalizedString("meeting_in_progress", comment: "How long a meeting has been running, e.g. '12 min in'"),
                minutes
            )
        }
    }
}

/// How the alert is chosen.
struct MeetingAlertPolicy: Equatable, Sendable {
    /// How long before the start the alert appears.
    var leadTime: TimeInterval
    /// How long after the start it keeps showing. Beyond this the meeting is
    /// either happening (and the user knows) or was skipped, and a permanent
    /// banner is just noise.
    var lingerAfterStart: TimeInterval
    /// Whether to surface events with no video-call link.
    var requiresMeetingLink: Bool

    static let `default` = MeetingAlertPolicy(
        leadTime: 2 * 60,
        lingerAfterStart: 5 * 60,
        requiresMeetingLink: false
    )
}

enum MeetingAlertSelector {
    /// The event that should be on screen at `now`, or nil.
    ///
    /// Filtering, in order:
    ///  - all-day events are never alerts: they have no start time to count
    ///    down to, and a birthday does not need a join button
    ///  - declined events are dropped; the user already said no
    ///  - reminders and birthdays are not meetings
    ///  - events the user dismissed stay dismissed for this run
    ///  - with `requiresMeetingLink`, only events that can actually be joined
    ///
    /// Of what survives, the one starting soonest wins — an in-progress
    /// meeting is preferred over a later one because it is the one you are
    /// currently late for.
    static func alert(
        from events: [EventModel],
        now: Date,
        policy: MeetingAlertPolicy = .default,
        dismissedEventIDs: Set<String> = []
    ) -> MeetingAlert? {
        let candidates = events.compactMap { event -> MeetingAlert? in
            guard !event.isAllDay else { return nil }
            guard !dismissedEventIDs.contains(event.id) else { return nil }
            guard isMeeting(event) else { return nil }
            if policy.requiresMeetingLink && event.meetingLink == nil { return nil }

            let untilStart = event.start.timeIntervalSince(now)

            if untilStart > 0 {
                guard untilStart <= policy.leadTime else { return nil }
                return MeetingAlert(
                    eventID: event.id,
                    title: event.title,
                    start: event.start,
                    end: event.end,
                    meetingLink: event.meetingLink,
                    timing: .startingSoon(seconds: untilStart)
                )
            }

            // Started already. Keep it while it is both within the linger
            // window and hasn't actually finished.
            let sinceStart = -untilStart
            guard sinceStart <= policy.lingerAfterStart, event.end > now else { return nil }
            return MeetingAlert(
                eventID: event.id,
                title: event.title,
                start: event.start,
                end: event.end,
                meetingLink: event.meetingLink,
                timing: .inProgress(seconds: sinceStart)
            )
        }

        // Earliest start wins, so an in-progress meeting beats one starting in
        // a minute — you are already late for the first.
        return candidates.min { $0.start < $1.start }
    }

    /// Birthdays and reminders share the event list but are not meetings.
    /// A declined event is one the user has already said no to.
    private static func isMeeting(_ event: EventModel) -> Bool {
        switch event.type {
        case .event(let attendance):
            return attendance != .declined
        case .birthday, .reminder:
            return false
        }
    }
}
