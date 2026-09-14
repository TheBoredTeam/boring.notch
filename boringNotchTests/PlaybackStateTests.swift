import XCTest
@testable import boringNotch

final class PlaybackStateMergeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)

    private func apply(_ json: String, to state: PlaybackState) throws -> PlaybackState {
        try JSONDecoder().decode(NowPlayingUpdate.self, from: Data(json.utf8)).applying(to: state, receivedAt: now)
    }

    private var track: PlaybackState {
        PlaybackState(bundleIdentifier: "com.apple.Music", capabilities: .appleMusic, isPlaying: true,
            title: "A", artist: "Artist", album: "Album", currentTime: 0, duration: 100,
            isShuffled: true, repeatMode: .one, lastUpdated: Date(timeIntervalSince1970: 90),
            artwork: Data([1, 2]), isFavorite: true)
    }

    func testNewTrackWithoutArtworkClearsTrackBoundFields() throws {
        let result = try apply(#"{"diff":true,"payload":{"title":"B"}}"#, to: track)
        XCTAssertEqual(result.title, "B")
        XCTAssertTrue(result.isPlaying)
        XCTAssertNil(result.artwork)
        XCTAssertFalse(result.isFavorite)
        XCTAssertFalse(result.isShuffled)
        XCTAssertEqual(result.repeatMode, .off)
        XCTAssertEqual(result.currentTime, 0)
        XCTAssertEqual(result.duration, 0)
        XCTAssertEqual(result.lastUpdated, now)
        XCTAssertEqual(result.capabilities, .unsupported)
    }

    func testElapsedOnlyDiffPreservesFavoriteArtworkAndMetadata() throws {
        let result = try apply(#"{"diff":true,"payload":{"elapsedTime":12}}"#, to: track)
        XCTAssertEqual(result.identity, track.identity)
        XCTAssertEqual(result.artwork, track.artwork)
        XCTAssertTrue(result.isFavorite)
        XCTAssertEqual(result.currentTime, 12)
        XCTAssertEqual(result.lastUpdated, now)
        XCTAssertEqual(result.capabilities, .appleMusic)
    }

    func testExplicitNullClearsButOmissionPreservesArtwork() throws {
        let cleared = try apply(#"{"diff":true,"payload":{"artworkData":null,"duration":null}}"#, to: track)
        XCTAssertNil(cleared.artwork)
        XCTAssertEqual(cleared.duration, 0)
        let unchanged = try apply(#"{"diff":true,"payload":{}}"#, to: track)
        XCTAssertEqual(unchanged, track)
    }

    func testSourceTransitionClearsTrackDataAndCapabilities() throws {
        let result = try apply(#"{"diff":true,"payload":{"bundleIdentifier":"com.google.Chrome.helper"}}"#, to: track)
        XCTAssertEqual(result.bundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(result.audioCaptureBundleIdentifiers, ["com.google.Chrome.helper"])
        XCTAssertNil(result.artwork)
        XCTAssertFalse(result.isFavorite)
        XCTAssertEqual(result.title, "")
        XCTAssertEqual(result.capabilities, .unsupported)
    }

    func testFullUpdateOmittingOptionalFieldsClearsThem() throws {
        let result = try apply(#"{"payload":{"bundleIdentifier":"com.apple.Music","title":"A","artist":"Artist","album":"Album"}}"#, to: track)
        XCTAssertEqual(result.identity, track.identity)
        XCTAssertNil(result.artwork)
        XCTAssertFalse(result.isFavorite)
        XCTAssertEqual(result.duration, 0)
        XCTAssertEqual(result.capabilities, .unsupported)
    }

    func testRestartAtSameNumericElapsedRebasesClock() throws {
        let result = try apply(#"{"diff":true,"payload":{"elapsedTime":0}}"#, to: track)
        XCTAssertEqual(result.currentTime, 0)
        XCTAssertEqual(result.lastUpdated, now)
    }

    func testTimestampOnlyRestartRetainsRawElapsedAtSourceTimestamp() throws {
        let initial = try apply(#"{"payload":{"bundleIdentifier":"com.apple.Music","title":"A","playing":true,"elapsedTime":0,"duration":300,"timestamp":"1970-01-01T00:01:40Z"}}"#, to: track)
        let update = try JSONDecoder().decode(NowPlayingUpdate.self,
            from: Data(#"{"diff":true,"payload":{"timestamp":"1970-01-01T00:02:10Z"}}"#.utf8))
        let result = update.applying(to: initial, receivedAt: now.addingTimeInterval(30))
        XCTAssertEqual(result.currentTime, 0)
        XCTAssertEqual(result.lastUpdated, now.addingTimeInterval(30))
    }

    func testDelayedTimestampOnlyDiffRetainsSourceTime() throws {
        let initial = try apply(#"{"payload":{"bundleIdentifier":"com.apple.Music","title":"A","playing":true,"elapsedTime":0,"duration":300,"timestamp":"1970-01-01T00:01:40Z"}}"#, to: track)
        let update = try JSONDecoder().decode(NowPlayingUpdate.self,
            from: Data(#"{"diff":true,"payload":{"timestamp":"1970-01-01T00:02:10Z"}}"#.utf8))
        let result = update.applying(to: initial, receivedAt: now.addingTimeInterval(35))
        XCTAssertEqual(result.currentTime, 0)
        XCTAssertEqual(result.lastUpdated, now.addingTimeInterval(30))
        XCTAssertEqual(PlaybackTime.position(elapsed: result.currentTime, duration: result.duration,
            rate: result.playbackRate, playing: result.isPlaying, sampledAt: result.lastUpdated,
            now: now.addingTimeInterval(35)), 5)
    }

    func testElapsedOnlyDiffRetainsRawSourceTimestamp() throws {
        let initial = try apply(#"{"payload":{"bundleIdentifier":"com.apple.Music","title":"A","playing":true,"elapsedTime":0,"duration":300,"timestamp":"1970-01-01T00:01:40Z"}}"#, to: track)
        let update = try JSONDecoder().decode(NowPlayingUpdate.self,
            from: Data(#"{"diff":true,"payload":{"elapsedTime":10}}"#.utf8))
        let result = update.applying(to: initial, receivedAt: now.addingTimeInterval(5))
        XCTAssertEqual(result.currentTime, 10)
        XCTAssertEqual(result.lastUpdated, now)
    }

    func testPauseResumeDoesNotReplaceRetainedRawSourceElapsed() throws {
        let initial = try apply(#"{"payload":{"bundleIdentifier":"com.apple.Music","title":"A","playing":true,"elapsedTime":0,"duration":300,"timestamp":"1970-01-01T00:01:40Z"}}"#, to: track)
        func update(_ json: String, _ state: PlaybackState, _ seconds: Double) throws -> PlaybackState {
            try JSONDecoder().decode(NowPlayingUpdate.self, from: Data(json.utf8))
                .applying(to: state, receivedAt: now.addingTimeInterval(seconds))
        }
        let paused = try update(#"{"diff":true,"payload":{"playing":false}}"#, initial, 10)
        XCTAssertEqual(paused.currentTime, 10)
        let resumed = try update(#"{"diff":true,"payload":{"playing":true}}"#, paused, 20)
        XCTAssertEqual(resumed.currentTime, 10)
        let restarted = try update(#"{"diff":true,"payload":{"timestamp":"1970-01-01T00:02:10Z"}}"#, resumed, 30)
        XCTAssertEqual(restarted.currentTime, 0)
        XCTAssertEqual(restarted.lastUpdated, now.addingTimeInterval(30))
    }

    func testPauseRebasesEstimatedElapsedWithoutAdvancingPausedClock() throws {
        let paused = try apply(#"{"diff":true,"payload":{"playing":false}}"#, to: track)
        XCTAssertEqual(paused.currentTime, 10)
        XCTAssertEqual(paused.lastUpdated, now)
        let resumed = try JSONDecoder().decode(NowPlayingUpdate.self,
            from: Data(#"{"diff":true,"payload":{"playing":true}}"#.utf8))
            .applying(to: paused, receivedAt: now.addingTimeInterval(30))
        XCTAssertEqual(resumed.currentTime, 10)
    }

    func testLateArtworkCannotRewindSeekOrTrack() throws {
        var sought = try apply(#"{"diff":true,"payload":{"elapsedTime":60}}"#, to: track)
        sought.applyArtwork(Data([3]), for: track.identity)
        XCTAssertEqual(sought.currentTime, 60)
        XCTAssertEqual(sought.lastUpdated, now)
        var next = try apply(#"{"diff":true,"payload":{"title":"B"}}"#, to: sought)
        next.applyArtwork(Data([4]), for: track.identity)
        XCTAssertNil(next.artwork)
        XCTAssertEqual(next.title, "B")
    }

    func testArtworkDoesNotParticipateInIdentity() {
        var changed = track
        changed.artwork = Data([7])
        XCTAssertEqual(changed.identity, track.identity)
        changed.trackIdentifier = "different"
        XCTAssertNotEqual(changed.identity, track.identity)
    }

    func testBrowserMusicSpotifyCapabilitiesFollowSource() throws {
        var state = try apply(#"{"payload":{"bundleIdentifier":"com.google.Chrome","title":"Video","shuffleMode":1,"repeatMode":1}}"#, to: track)
        XCTAssertEqual(state.capabilities, .unsupported)
        state = try apply(#"{"payload":{"bundleIdentifier":"com.apple.Music","title":"Song","shuffleMode":1,"repeatMode":1}}"#, to: state)
        XCTAssertEqual(state.capabilities?.repeatModes, [.off, .all, .one])
        XCTAssertFalse(state.capabilities?.favorite ?? true) // Must query this track successfully.
        state = try apply(#"{"payload":{"bundleIdentifier":"com.spotify.client","title":"Song","shuffleMode":1,"repeatMode":1}}"#, to: state)
        XCTAssertEqual(state.capabilities, .spotify)
    }
}
