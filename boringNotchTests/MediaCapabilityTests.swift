import Combine
import XCTest
@testable import boringNotch

final class MediaCapabilityTests: XCTestCase {
    @MainActor
    func testManagerDoesNotDispatchUnavailableControls() async {
        let controller = RecordingMediaController(capabilities: .unsupported)
        let manager = MusicManager(controller: controller, type: .appleMusic)
        defer { manager.destroy() }

        manager.setFavorite(true)
        manager.toggleShuffle()
        manager.toggleRepeat()
        await Task.yield()

        XCTAssertTrue(controller.commands.isEmpty)
    }

    @MainActor
    func testManagerDispatchesAvailableControlsDirectly() async {
        let controller = RecordingMediaController(capabilities: .appleMusic)
        let manager = MusicManager(controller: controller, type: .appleMusic)
        defer { manager.destroy() }
        let dispatched = expectation(description: "provider commands dispatched")
        dispatched.expectedFulfillmentCount = 3
        controller.onCommand = { dispatched.fulfill() }

        manager.setFavorite(true)
        manager.toggleShuffle()
        manager.toggleRepeat()

        await fulfillment(of: [dispatched], timeout: 1)
        XCTAssertEqual(Set(controller.commands), ["favorite", "shuffle", "repeat"])
    }

    @MainActor
    func testSourcePublishedFavoriteStateIsAuthoritative() async {
        let controller = RecordingMediaController(capabilities: .appleMusic)
        let manager = MusicManager(controller: controller, type: .appleMusic)
        defer { manager.destroy() }
        let accepted = expectation(description: "source state accepted")
        let subscription = manager.$isFavoriteTrack
            .filter { $0 }
            .prefix(1)
            .sink { _ in accepted.fulfill() }

        controller.state.isFavorite = true

        await fulfillment(of: [accepted], timeout: 1)
        XCTAssertTrue(manager.isFavoriteTrack)
        withExtendedLifetime(subscription) {}
    }

    func testRepeatCyclesOnlyThroughSupportedModes() {
        XCTAssertEqual(MediaCapabilities.spotify.nextRepeatMode(after: .off), .all)
        XCTAssertEqual(MediaCapabilities.spotify.nextRepeatMode(after: .all), .off)
        XCTAssertEqual(MediaCapabilities.appleMusic.nextRepeatMode(after: .all), .one)
        XCTAssertNil(MediaCapabilities.unsupported.nextRepeatMode(after: .off))
    }
}

@MainActor
private final class RecordingMediaController: MediaControllerProtocol {
    @Published var state: PlaybackState
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { $state.eraseToAnyPublisher() }
    var supportsVolumeControl: Bool { false }
    var supportsFavorite: Bool { capabilities.favorite }
    var capabilities: MediaCapabilities { state.capabilities ?? .unsupported }
    var commands: [String] = []
    var onCommand: (() -> Void)?

    init(capabilities: MediaCapabilities) {
        state = PlaybackState(
            bundleIdentifier: "com.apple.Music",
            capabilities: capabilities,
            lastUpdated: Date()
        )
    }

    func setFavorite(_ favorite: Bool) async {
        commands.append("favorite")
        onCommand?()
    }
    func toggleShuffle() async {
        commands.append("shuffle")
        onCommand?()
    }
    func toggleRepeat() async {
        commands.append("repeat")
        onCommand?()
    }
    func play() async {}
    func pause() async {}
    func seek(to time: Double) async {}
    func nextTrack() async {}
    func previousTrack() async {}
    func togglePlay() async {}
    func setVolume(_ level: Double) async {}
    func isActive() -> Bool { false }
    func updatePlaybackInfo() async {}
}
