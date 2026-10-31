// SPDX-License-Identifier: GPL-3.0-only

import XCTest

@testable import boringNotch

final class NowPlayingFavoriteTests: XCTestCase {
    func testAdapterBooleanPayloadsAndMissingCapabilityDecode() throws {
        let decoder = JSONDecoder()
        let liked = try decoder.decode(NowPlayingUpdate.self, from: Data(#"{"diff":false,"payload":{"supportsIsLiked":true,"isLiked":true}}"#.utf8))
        XCTAssertEqual(liked.payload.supportsIsLiked, true)
        XCTAssertEqual(liked.payload.isLiked, true)
        let unliked = try decoder.decode(NowPlayingUpdate.self, from: Data(#"{"diff":true,"payload":{"isLiked":false}}"#.utf8))
        XCTAssertNil(unliked.payload.supportsIsLiked)
        XCTAssertEqual(unliked.payload.isLiked, false)
        let unsupported = try decoder.decode(NowPlayingUpdate.self, from: Data(#"{"diff":false,"payload":{}}"#.utf8))
        XCTAssertNil(unsupported.payload.supportsIsLiked)
    }

    func testPlaybackOnlyDiffPreservesTheConfirmedLike() {
        let previous = NowPlayingFavoriteSnapshot(bundleIdentifier: "test.player", enabled: true, active: true)
        XCTAssertEqual(previous, .merging(bundleIdentifier: "test.player", enabled: nil, active: nil, previous: previous, preserving: true))
        let unliked = NowPlayingFavoriteSnapshot.merging(bundleIdentifier: "test.player", enabled: nil, active: false, previous: previous, preserving: true)
        XCTAssertTrue(unliked.enabled)
        XCTAssertFalse(unliked.active)
    }

    func testNewItemOrPlayerDoesNotInheritOldFeedback() {
        let previous = NowPlayingFavoriteSnapshot(bundleIdentifier: "first.player", enabled: true, active: true)
        for (bundle, preserving) in [("first.player", false), ("second.player", true)] {
            let next = NowPlayingFavoriteSnapshot.merging(bundleIdentifier: bundle, enabled: nil, active: nil, previous: previous, preserving: preserving)
            XCTAssertFalse(next.enabled)
            XCTAssertFalse(next.active)
        }
    }

    func testCommandCanBeDisabledWithoutChangingTrack() {
        let previous = NowPlayingFavoriteSnapshot(bundleIdentifier: "test.player", enabled: true, active: true)
        let disabled = NowPlayingFavoriteSnapshot.merging(bundleIdentifier: "test.player", enabled: false, active: false, previous: previous, preserving: true)
        XCTAssertFalse(disabled.supports(NowPlayingFavoriteContext(PlaybackState(bundleIdentifier: "test.player"))))
    }

    func testOnlyEnabledCommandForTheCurrentPlayerIsSupported() {
        let context = NowPlayingFavoriteContext(PlaybackState(bundleIdentifier: "test.player"))
        XCTAssertTrue(NowPlayingFavoriteSnapshot(bundleIdentifier: "test.player", enabled: true, active: false).supports(context))
        XCTAssertFalse(NowPlayingFavoriteSnapshot(bundleIdentifier: "test.player", enabled: false, active: true).supports(context))
        XCTAssertFalse(NowPlayingFavoriteSnapshot(bundleIdentifier: "other.player", enabled: true, active: true).supports(context))
        XCTAssertFalse(NowPlayingFavoriteSnapshot(bundleIdentifier: "", enabled: true, active: true).supports(NowPlayingFavoriteContext(PlaybackState(bundleIdentifier: ""))))
    }

    func testTrackOrPlayerChangeInvalidatesTheReadContext() {
        var state = PlaybackState(bundleIdentifier: "test.player")
        state.title = "First"
        state.artist = "Artist"
        state.album = "Album"
        state.duration = 180
        let original = NowPlayingFavoriteContext(state)
        state.currentTime = 24
        state.isPlaying = true
        state.isFavorite = true
        XCTAssertEqual(original, NowPlayingFavoriteContext(state))
        for keyPath in [\PlaybackState.title, \.artist, \.album, \.bundleIdentifier] {
            var changed = state
            changed[keyPath: keyPath] += " changed"
            XCTAssertNotEqual(original, NowPlayingFavoriteContext(changed))
        }
        state.duration = 240
        XCTAssertEqual(original, NowPlayingFavoriteContext(state), "duration corrections are playback diffs, not a new item")
    }
}
