// SPDX-License-Identifier: GPL-3.0-only

import XCTest

@testable import boringNotch

final class NowPlayingFavoriteTests: XCTestCase {
    func testAdapterCommandListDecodesExplicitActiveState() throws {
        let decoder = JSONDecoder()
        let liked = try decoder.decode(NowPlayingUpdate.self, from: Data(#"{"diff":false,"payload":{"supportedCommands":[{"id":21,"enabled":true,"options":{"kMRMediaRemoteCommandInfoIsActiveKey":true}}]}}"#.utf8))
        XCTAssertEqual(liked.payload.likeCommandEnabled, true)
        XCTAssertEqual(liked.payload.likeCommandActive, true)
        let unliked = try decoder.decode(NowPlayingUpdate.self, from: Data(#"{"diff":true,"payload":{"supportedCommands":[{"id":21,"enabled":true,"options":{"kMRMediaRemoteCommandInfoIsActiveKey":false}}]}}"#.utf8))
        XCTAssertEqual(unliked.payload.likeCommandEnabled, true)
        XCTAssertEqual(unliked.payload.likeCommandActive, false)
        let unsupported = try decoder.decode(NowPlayingUpdate.self, from: Data(#"{"diff":false,"payload":{"supportsIsLiked":true,"isLiked":true}}"#.utf8))
        XCTAssertNil(unsupported.payload.likeCommandEnabled)
    }

    func testPlaybackOnlyDiffPreservesTheConfirmedLike() {
        let previous = NowPlayingFavoriteSnapshot(bundleIdentifier: "test.player", enabled: true, active: true)
        XCTAssertEqual(previous, .merging(bundleIdentifier: "test.player", enabled: nil, active: nil, previous: previous, preserving: true))
        let unliked = NowPlayingFavoriteSnapshot.merging(bundleIdentifier: "test.player", enabled: nil, active: false, previous: previous, preserving: true)
        XCTAssertTrue(unliked.enabled)
        XCTAssertFalse(unliked.active)
    }

    func testSameTrackAdapterDiffClearsRemovedCommandState() throws {
        let previous = NowPlayingFavoriteSnapshot(bundleIdentifier: "test.player", enabled: true, active: true)
        func apply(_ json: String) throws -> NowPlayingFavoriteSnapshot {
            let update = try JSONDecoder().decode(NowPlayingUpdate.self, from: Data(json.utf8))
            return .merging(bundleIdentifier: previous.bundleIdentifier,
                            enabled: update.payload.likeCommandEnabled, active: update.payload.likeCommandActive,
                            previous: previous, preserving: update.diff == true)
        }
        XCTAssertEqual(try apply(#"{"diff":true,"payload":{"elapsedTime":5}}"#), previous)

        let cleared = try apply(#"{"diff":true,"payload":{"supportedCommands":[{"id":21,"enabled":true,"options":{"other":123}}]}}"#)
        XCTAssertFalse(cleared.enabled)
        XCTAssertFalse(cleared.active)

        let disabled = try apply(#"{"diff":true,"payload":{"supportedCommands":null}}"#)
        XCTAssertFalse(disabled.enabled)
        XCTAssertFalse(disabled.active)

        let empty = try apply(#"{"diff":true,"payload":{"supportedCommands":[]}}"#)
        XCTAssertEqual(empty, disabled)
        let unavailable = try apply(#"{"diff":true,"payload":{"supportedCommands":[{"id":21,"enabled":false,"options":{"kMRMediaRemoteCommandInfoIsActiveKey":true}}]}}"#)
        XCTAssertFalse(unavailable.enabled)
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
