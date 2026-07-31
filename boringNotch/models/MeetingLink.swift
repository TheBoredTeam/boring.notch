//
//  MeetingLink.swift
//  boringNotch
//

import Foundation

/// A video-conferencing service recognised on calendar events.
enum MeetingProvider: String, Codable, CaseIterable, Sendable {
    case googleMeet
    case zoom
    case teams
    case webex
    case whereby
    case jitsi

    /// Human-readable name, used in the accessibility label.
    var displayName: String {
        switch self {
        case .googleMeet: return "Google Meet"
        case .zoom: return "Zoom"
        case .teams: return "Microsoft Teams"
        case .webex: return "Webex"
        case .whereby: return "Whereby"
        case .jitsi: return "Jitsi"
        }
    }

    /// Host suffixes that identify this provider. A host matches when it equals a
    /// suffix exactly or ends with "." + suffix, so `acme.zoom.us` matches `zoom.us`
    /// while `notzoom.us` does not.
    var hostSuffixes: [String] {
        switch self {
        case .googleMeet: return ["meet.google.com", "hangouts.google.com"]
        case .zoom: return ["zoom.us", "zoomgov.com"]
        case .teams: return ["teams.microsoft.com", "teams.live.com"]
        case .webex: return ["webex.com"]
        case .whereby: return ["whereby.com"]
        case .jitsi: return ["meet.jit.si"]
        }
    }

    static func provider(forHost host: String) -> MeetingProvider? {
        let host = host.lowercased()
        for provider in MeetingProvider.allCases {
            for suffix in provider.hostSuffixes where host == suffix || host.hasSuffix("." + suffix) {
                return provider
            }
        }
        return nil
    }
}

/// A join URL discovered on a calendar event, plus the service it belongs to.
struct MeetingLink: Equatable, Codable, Sendable {
    let url: URL
    let provider: MeetingProvider
}
