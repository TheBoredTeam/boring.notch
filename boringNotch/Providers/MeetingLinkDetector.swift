//
//  MeetingLinkDetector.swift
//  boringNotch
//

import Foundation

/// Finds a video-meeting join URL on a calendar event.
///
/// EventKit exposes no public API for conference links, so the URL is recovered by
/// parsing the event's own text fields. Detection is deliberately conservative:
/// only known provider hosts count, and the structured fields outrank free text so
/// an unrelated link in a long description cannot beat the organiser's own values.
enum MeetingLinkDetector {

    /// Field priority: `url` then `location` then `notes`. First classified match wins.
    static func detect(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        if let url, let link = classify(url) { return link }
        if let location, let link = firstLink(in: location) { return link }
        if let notes, let link = firstLink(in: notes) { return link }
        return nil
    }

    /// First recognised meeting URL in a block of free text.
    static func firstLink(in text: String) -> MeetingLink? {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var found: MeetingLink?
        detector.enumerateMatches(in: text, options: [], range: range) { match, _, stop in
            guard let url = match?.url, let link = classify(url) else { return }
            found = link
            stop.pointee = true
        }
        return found
    }

    /// Maps a URL to a provider, or nil if the host is not a known meeting service.
    static func classify(_ url: URL) -> MeetingLink? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(),
              let provider = MeetingProvider.provider(forHost: host)
        else { return nil }
        return MeetingLink(url: url, provider: provider)
    }
}
