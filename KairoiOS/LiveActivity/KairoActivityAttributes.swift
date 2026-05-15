//
//  KairoActivityAttributes.swift
//  KairoiOS — Live Activity definition
//
//  Shared between the iOS app (which starts/updates/ends activities) and
//  the Widget Extension (which renders them). Keep this file in BOTH
//  the app target and the widget extension target's compile sources.
//

import ActivityKit
import Foundation

struct KairoActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    /// Mutable state — updated as Kairo's state changes on the user's Mac.
    public struct State: Codable, Hashable {
        public enum Mode: String, Codable {
            case idle        // dormant — Mac is on, nothing happening
            case listening   // Kairo is hearing the user
            case thinking    // brain is composing a response
            case speaking    // Kairo is replying with TTS
            case nowPlaying  // music is playing on the user's Mac
        }

        public let mode: Mode
        public let primaryText: String   // e.g. "Listening…" / song title
        public let secondaryText: String? // e.g. artist name / nothing
        public let timestamp: Date       // when this state began

        public init(mode: Mode, primaryText: String, secondaryText: String? = nil, timestamp: Date = Date()) {
            self.mode = mode
            self.primaryText = primaryText
            self.secondaryText = secondaryText
            self.timestamp = timestamp
        }
    }

    /// Immutable attributes — set once when the activity starts.
    public let macDeviceName: String  // "John's Mac"
    public let sessionID: String      // for pairing
}
