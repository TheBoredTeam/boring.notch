import Combine
import XCTest
@testable import boringNotch

@MainActor
final class MediaCommandLifetimeTests: XCTestCase {
    private var subscriptions = Set<AnyCancellable>()

    func testSuspendedCommandExpiresAndLateCompletionCannotRefreshNewCommand() async {
        let controller = SuspendedMediaController()
        let manager = MusicManager(controller: controller, type: .appleMusic, commandTimeout: .milliseconds(100))
        defer {
            controller.releaseAll()
            manager.destroy()
            subscriptions.removeAll()
        }
        await acceptInitialState(manager)
        let expired = expectation(description: "command expires while provider is suspended")
        manager.$mediaCommandStatus.filter { $0 == .failed }.prefix(1)
            .sink { _ in expired.fulfill() }.store(in: &subscriptions)
        manager.setFavorite(true)
        XCTAssertEqual(manager.mediaCommandStatus, .pending)
        await fulfillment(of: [expired], timeout: 0.5)
        XCTAssertEqual(manager.mediaCommandStatus, .failed)
        XCTAssertEqual(controller.refreshCount, 0)

        manager.toggleShuffle()
        XCTAssertEqual(manager.mediaCommandStatus, .pending)
        controller.releaseCommand()
        await drainMainActor()
        XCTAssertEqual(manager.mediaCommandStatus, .pending)
        XCTAssertEqual(controller.refreshCount, 1, "only the new shuffle command may refresh")
        controller.state.isShuffled = true
        await drainMainActor()
        XCTAssertEqual(manager.mediaCommandStatus, .confirmed)
    }

    func testSuspendedRefreshExpiresAndLateReturnCannotCompleteNextCommand() async {
        let controller = SuspendedMediaController()
        controller.suspendCommand = false
        controller.suspendRefresh = true
        let manager = MusicManager(controller: controller, type: .appleMusic, commandTimeout: .milliseconds(100))
        defer {
            controller.releaseAll()
            manager.destroy()
            subscriptions.removeAll()
        }
        await acceptInitialState(manager)
        let expired = expectation(description: "refresh expires while provider is suspended")
        manager.$mediaCommandStatus.filter { $0 == .failed }.prefix(1)
            .sink { _ in expired.fulfill() }.store(in: &subscriptions)
        manager.setFavorite(true)
        await fulfillment(of: [expired], timeout: 0.5)
        XCTAssertEqual(manager.mediaCommandStatus, .failed)
        XCTAssertEqual(controller.refreshCount, 1)

        controller.suspendRefresh = false
        manager.toggleShuffle()
        controller.releaseRefresh()
        await drainMainActor()
        XCTAssertEqual(manager.mediaCommandStatus, .pending)
        XCTAssertEqual(controller.refreshCount, 2)
        controller.state.isShuffled = true
        await drainMainActor()
        XCTAssertEqual(manager.mediaCommandStatus, .confirmed)
    }

    func testConfirmationAndIdentityChangeCancelDeadline() async {
        let controller = SuspendedMediaController()
        controller.suspendCommand = false
        let manager = MusicManager(controller: controller, type: .appleMusic, commandTimeout: .milliseconds(50))
        defer {
            controller.releaseAll()
            manager.destroy()
            subscriptions.removeAll()
        }
        await acceptInitialState(manager)
        manager.setFavorite(true)
        controller.state.isFavorite = true
        await drainMainActor()
        XCTAssertEqual(manager.mediaCommandStatus, .confirmed)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(manager.mediaCommandStatus, .confirmed)

        manager.toggleShuffle()
        controller.state.trackIdentifier = "another-track"
        await drainMainActor()
        XCTAssertEqual(manager.mediaCommandStatus, .idle)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(manager.mediaCommandStatus, .idle)
    }

    private func acceptInitialState(_ manager: MusicManager) async {
        let accepted = expectation(description: "initial state accepted")
        manager.$bundleIdentifier.compactMap { $0 }.prefix(1)
            .sink { _ in accepted.fulfill() }.store(in: &subscriptions)
        await fulfillment(of: [accepted], timeout: 1)
    }

    private func drainMainActor() async {
        // The manager receives the controller publisher on DispatchQueue.main.
        // Enqueue a barrier after its emissions rather than sleeping for them.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        await Task.yield()
    }
}

@MainActor
private final class SuspendedMediaController: MediaControllerProtocol {
    // No real source, artwork or title: constructing this controller cannot
    // start AppleScript, media capture, lyrics requests, or playback services.
    @Published var state = PlaybackState(bundleIdentifier: "", capabilities: .appleMusic, lastUpdated: Date())
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { $state.eraseToAnyPublisher() }
    var supportsVolumeControl: Bool { false }
    var supportsFavorite: Bool { true }
    var capabilities: MediaCapabilities { .appleMusic }
    var suspendCommand = true
    var suspendRefresh = false
    var refreshCount = 0
    private var commandContinuation: CheckedContinuation<Void, Never>?
    private var refreshContinuation: CheckedContinuation<Void, Never>?

    func setFavorite(_ favorite: Bool) async {
        if suspendCommand {
            await withCheckedContinuation { commandContinuation = $0 }
        }
    }
    func updatePlaybackInfo() async {
        refreshCount += 1
        if suspendRefresh {
            await withCheckedContinuation { refreshContinuation = $0 }
        }
    }
    func releaseCommand() {
        let continuation = commandContinuation
        commandContinuation = nil
        continuation?.resume()
    }
    func releaseRefresh() {
        let continuation = refreshContinuation
        refreshContinuation = nil
        continuation?.resume()
    }
    func releaseAll() {
        releaseCommand()
        releaseRefresh()
    }
    func toggleShuffle() async {}
    func toggleRepeat() async {}
    func play() async {}
    func pause() async {}
    func seek(to time: Double) async {}
    func nextTrack() async {}
    func previousTrack() async {}
    func togglePlay() async {}
    func setVolume(_ level: Double) async {}
    func isActive() -> Bool { false }
}
