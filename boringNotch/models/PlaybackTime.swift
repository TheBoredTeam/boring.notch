//
//  PlaybackTime.swift
//  boringNotch
//

import Foundation

/// Formats a playback position as `m:ss`, or `h:mm:ss` past the hour.
enum PlaybackTime {
    static func string(from seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }

        // A negative position is meaningless and used to render as "-1:-1"; clamp instead.
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
