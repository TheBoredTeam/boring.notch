import AppKit
import Defaults
import EventKit
import Foundation

nonisolated enum MeetingLinkDetector {
    private static let allowedHostFragments = [
        "zoom.us",
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "webex.com",
    ]

    static func find(in candidates: [String]) -> URL? {
        for candidate in candidates {
            if let direct = URL(string: candidate), isAllowed(direct) {
                return direct
            }

            guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
                continue
            }
            let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
            for match in detector.matches(in: candidate, range: range) {
                if let url = match.url, isAllowed(url) {
                    return url
                }
            }
        }
        return nil
    }

    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return allowedHostFragments.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}

@MainActor
final class MeetingActivityManager: ObservableObject {
    static let shared = MeetingActivityManager()

    @Published private(set) var nextMeeting: EventModel?
    @Published private(set) var joinURL: URL?
    @Published private(set) var isLoading = false

    private var refreshTask: Task<Void, Never>?
    private var notifiedMeetingID: String?

    private init() {
        if Defaults[.meetingCardEnabled] {
            startMonitoring()
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func startMonitoring() {
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
        nextMeeting = nil
        joinURL = nil
    }

    func refreshConfiguration() {
        Defaults[.meetingCardEnabled] ? startMonitoring() : stopMonitoring()
    }

    func requestAccessAndRefresh() async {
        await CalendarManager.shared.checkCalendarAuthorization()
        await refresh()
    }

    func refresh() async {
        guard Defaults[.meetingCardEnabled], authorizationStatus == .fullAccess else {
            nextMeeting = nil
            joinURL = nil
            return
        }

        isLoading = true
        let days = min(max(Defaults[.meetingLookAheadDays], 1), 30)
        let end = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let events = await CalendarManager.shared.upcomingEvents(to: end)
        let meeting = events.first { event in
            event.attendance != .declined && (event.isMeeting || Self.findJoinURL(in: event) != nil)
        } ?? events.first

        nextMeeting = meeting
        joinURL = meeting.flatMap(Self.findJoinURL)
        isLoading = false

        if let meeting {
            let secondsUntilStart = meeting.start.timeIntervalSinceNow
            if secondsUntilStart >= 0, secondsUntilStart <= 10 * 60,
               notifiedMeetingID != meeting.id
            {
                notifiedMeetingID = meeting.id
                BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .meeting)
            }
        }
    }

    func join() {
        guard let joinURL else { return }
        NSWorkspace.shared.open(joinURL)
    }

    private static func findJoinURL(in event: EventModel) -> URL? {
        let candidates = [event.url?.absoluteString, event.location, event.notes]
            .compactMap { $0 }
        return MeetingLinkDetector.find(in: candidates)
    }
}
