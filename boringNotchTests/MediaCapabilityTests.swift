import Combine
import XCTest
@testable import boringNotch

final class MediaCapabilityTests: XCTestCase {
    @MainActor
    func testUnsupportedCommandsNeverReachController() async {
        let controller = RecordingMediaController()
        for command in [MediaCommand.favorite(true), .shuffle(true), .repeatMode(.one)] {
            let sent = await command.perform(on: controller, capabilities: .unsupported)
            XCTAssertFalse(sent)
        }
        let repeatOne = await MediaCommand.repeatMode(.one).perform(on: controller, capabilities: .spotify)
        let favorite = await MediaCommand.favorite(true).perform(on: controller, capabilities: .spotify)
        XCTAssertFalse(repeatOne)
        XCTAssertFalse(favorite)
        XCTAssertTrue(controller.commands.isEmpty)
    }

    @MainActor
    func testSupportedCommandsAreDispatchedWithoutOptimisticState() async {
        let controller = RecordingMediaController()
        let shuffle = MediaCommand.shuffle(true)
        let repeatMode = MediaCommand.repeatMode(.all)
        let sentShuffle = await shuffle.perform(on: controller, capabilities: .spotify)
        let sentRepeat = await repeatMode.perform(on: controller, capabilities: .spotify)
        XCTAssertTrue(sentShuffle)
        XCTAssertTrue(sentRepeat)
        XCTAssertEqual(controller.commands, ["shuffle", "repeat"])
        XCTAssertFalse(shuffle.isConfirmed(by: controller.state))
        XCTAssertFalse(repeatMode.isConfirmed(by: controller.state))
    }

    @MainActor
    func testFavoriteSourceUpdateWhileCommandIsPendingIsAuthoritative() async {
        let controller = RecordingMediaController()
        controller.confirmFavorite = true
        let command = MediaCommand.favorite(true)
        let sent = await command.perform(on: controller, capabilities: .appleMusic)
        XCTAssertTrue(sent)
        XCTAssertTrue(command.isConfirmed(by: controller.state))
        XCTAssertEqual(controller.commands, ["favorite"])
    }

    func testRepeatCyclesOnlyThroughSupportedModes() {
        XCTAssertEqual(MediaCapabilities.spotify.nextRepeatMode(after: .off), .all)
        XCTAssertEqual(MediaCapabilities.spotify.nextRepeatMode(after: .all), .off)
        XCTAssertEqual(MediaCapabilities.appleMusic.nextRepeatMode(after: .all), .one)
        XCTAssertNil(MediaCapabilities.unsupported.nextRepeatMode(after: .off))
    }

    @MainActor
    func testTrackWithoutFavoriteSupportCannotBeFavorited() async {
        let controller = RecordingMediaController()
        var capabilities = MediaCapabilities.appleMusic
        capabilities.favorite = false
        let sent = await MediaCommand.favorite(true).perform(on: controller, capabilities: capabilities)
        XCTAssertFalse(sent)
        XCTAssertTrue(controller.commands.isEmpty)
    }
}

@MainActor
private final class RecordingMediaController: MediaControllerProtocol {
    @Published var state = PlaybackState(bundleIdentifier: "com.apple.Music")
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { $state.eraseToAnyPublisher() }
    var supportsVolumeControl: Bool { false }
    var supportsFavorite: Bool { true }
    var commands: [String] = []
    var confirmFavorite = false
    func setFavorite(_ favorite: Bool) async {
        commands.append("favorite")
        if confirmFavorite { state.isFavorite = favorite }
        await Task.yield()
    }
    func toggleShuffle() async { commands.append("shuffle") }
    func toggleRepeat() async { commands.append("repeat") }
    func play() async {}
    func pause() async {}
    func seek(to time: Double) async {}
    func nextTrack() async {}
    func previousTrack() async {}
    func togglePlay() async {}
    func setVolume(_ level: Double) async {}
    func isActive() -> Bool { true }
    func updatePlaybackInfo() async {}
}
