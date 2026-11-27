// SPDX-License-Identifier: GPL-3.0-only

import Foundation

struct NowPlayingFavoriteContext: Equatable {
    let bundleIdentifier: String
    let title: String
    let artist: String
    let album: String

    init(_ state: PlaybackState) {
        bundleIdentifier = state.bundleIdentifier
        title = state.title
        artist = state.artist
        album = state.album
    }
}

/// Capability and accepted state from MediaRemote Adapter's current item.
struct NowPlayingFavoriteSnapshot: Equatable, Sendable {
    let bundleIdentifier: String
    let enabled: Bool
    let active: Bool

    func supports(_ context: NowPlayingFavoriteContext) -> Bool {
        enabled && !context.bundleIdentifier.isEmpty && bundleIdentifier == context.bundleIdentifier
    }

    static func merging(
        bundleIdentifier: String,
        enabled: Bool?,
        active: Bool?,
        previous: Self?,
        preserving: Bool
    ) -> Self {
        let previous = preserving && previous?.bundleIdentifier == bundleIdentifier ? previous : nil
        return Self(
            bundleIdentifier: bundleIdentifier,
            enabled: enabled ?? previous?.enabled ?? false,
            active: active ?? previous?.active ?? false
        )
    }
}
