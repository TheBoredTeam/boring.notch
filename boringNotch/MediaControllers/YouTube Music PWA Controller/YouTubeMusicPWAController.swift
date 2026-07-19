//
//  YouTubeMusicPWAController.swift
//  boringNotch
//
//  Media controller for the official YouTube Music web player, bridged through the
//  Boring Notch browser extension.
//
//  This is deliberately separate from `YouTubeMusicController`, which drives the
//  third-party Pear Desktop app over its localhost API. Both can coexist; users pick
//  one in Settings.
//
//  Unlike every other controller here, there is no local application to inspect: the
//  player lives in a browser tab. So "is this source active" is answered by whether the
//  extension is currently connected rather than by scanning running applications.
//

import AppKit
import Combine
import Defaults
import Foundation

/// `@unchecked Sendable` is required because the bridge server hands state back through
/// `@Sendable` callbacks. It is sound here: every stored mutable property
/// (`playbackState`, `artworkFetchTask`, `lastArtworkURL`) is only ever touched from the
/// `@MainActor` methods below, and the one property read off the main actor — `liveness`,
/// via `isActive()` — does its own locking.
final class YouTubeMusicPWAController: MediaControllerProtocol, @unchecked Sendable {
    @Published private var playbackState = PlaybackState(
        bundleIdentifier: YouTubeMusicPWAController.resolveBundleIdentifier()
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool { true }
    var supportsFavorite: Bool { true }

    private let server: BrowserBridgeServer
    private let liveness: BrowserBridgeLiveness
    private var artworkFetchTask: Task<Void, Never>?
    private var lastArtworkURL: String?

    // MARK: - Lifecycle

    init(
        port: UInt16 = UInt16(clamping: Defaults[.browserBridgePort]),
        token: String = BrowserBridgePairing.token
    ) {
        let configuration = BrowserBridgeConfiguration(
            port: port,
            clientTimeout: BrowserBridgeConfiguration.default.clientTimeout
        )
        self.server = BrowserBridgeServer(configuration: configuration, token: token)
        self.liveness = server.livenessProbe

        Task { [weak self] in
            guard let self else { return }
            await self.server.setHandlers(
                onState: { [weak self] state in
                    Task { @MainActor [weak self] in
                        self?.apply(state)
                    }
                },
                onConnectionChange: { [weak self] connected in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if connected {
                            NotificationCenter.default.post(
                                name: .browserBridgeConnectionChanged, object: nil
                            )
                        } else {
                            self.resetPlaybackState()
                            NotificationCenter.default.post(
                                name: .browserBridgeConnectionChanged, object: nil
                            )
                        }
                    }
                }
            )
            do {
                try await self.server.start()
            } catch {
                NSLog("[YouTubeMusicPWAController] Failed to start bridge: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        artworkFetchTask?.cancel()
        let server = self.server
        Task.detached { await server.stop() }
    }

    // MARK: - MediaControllerProtocol

    func play() async { await server.send(.play) }
    func pause() async { await server.send(.pause) }
    func togglePlay() async { await server.send(.toggle) }
    func nextTrack() async { await server.send(.next) }
    func previousTrack() async { await server.send(.previous) }
    func toggleShuffle() async { await server.send(.toggleShuffle) }
    func toggleRepeat() async { await server.send(.toggleRepeat) }

    func seek(to time: Double) async {
        await server.send(.seek, value: max(0, time))
    }

    func setVolume(_ level: Double) async {
        await server.send(.setVolume, value: max(0.0, min(1.0, level)))
    }

    func setFavorite(_ favorite: Bool) async {
        await server.send(.setFavorite, value: favorite ? 1 : 0)
    }

    /// True while a browser extension is connected and sending keepalives.
    ///
    /// Must stay cheap and synchronous — the protocol calls this from non-async
    /// contexts — so it reads a lock-guarded timestamp instead of probing the actor.
    func isActive() -> Bool {
        liveness.isAlive
    }

    /// The extension pushes state as it changes, so there is nothing to poll. Asking the
    /// page for a fresh snapshot is still useful when the app wants to force a refresh.
    func updatePlaybackInfo() async {
        guard isActive() else {
            await MainActor.run { self.resetPlaybackState() }
            return
        }
    }

    // MARK: - State mapping

    @MainActor
    private func apply(_ incoming: BrowserBridgeTrackState) {
        var newState = playbackState

        newState.isPlaying = incoming.isPlaying
        if let title = incoming.title { newState.title = title }
        if let artist = incoming.artist { newState.artist = artist }
        if let album = incoming.album { newState.album = album }
        if let duration = incoming.duration, duration.isFinite, duration >= 0 {
            newState.duration = duration
        }
        if let position = incoming.position, position.isFinite, position >= 0 {
            newState.currentTime = position
        }
        if let volume = incoming.volume {
            newState.volume = max(0.0, min(1.0, volume))
        }
        if let favorite = incoming.isFavorite { newState.isFavorite = favorite }
        if let mode = incoming.repeatMode {
            switch mode.lowercased() {
            case "one": newState.repeatMode = .one
            case "all": newState.repeatMode = .all
            default: newState.repeatMode = .off
            }
        }
        newState.lastUpdated = Date()

        if newState != playbackState {
            playbackState = newState
        }

        updateArtworkIfNeeded(incoming.artworkUrl)
    }

    @MainActor
    private func updateArtworkIfNeeded(_ urlString: String?) {
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else { return }
        // Artwork only changes on track change; refetching per state message would hammer
        // the network for no benefit.
        guard urlString != lastArtworkURL else { return }
        lastArtworkURL = urlString

        artworkFetchTask?.cancel()
        artworkFetchTask = Task { [weak self] in
            do {
                let data = try await ImageService.shared.fetchImageData(from: url)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.playbackState.artwork = data
                }
            } catch {
                // Artwork is decorative; a failure should never disturb playback state.
            }
        }
    }

    @MainActor
    private func resetPlaybackState() {
        artworkFetchTask?.cancel()
        artworkFetchTask = nil
        lastArtworkURL = nil
        playbackState = PlaybackState(
            bundleIdentifier: Self.resolveBundleIdentifier(),
            isPlaying: false
        )
    }

    // MARK: - Browser identification

    /// Best-effort bundle identifier for whichever browser is hosting the player.
    ///
    /// Drives the app icon shown in the notch and what "open music app" launches. A
    /// YouTube Music PWA installed from Chrome gets its own `com.google.Chrome.app.*`
    /// bundle, which is a much better answer than the browser itself, so prefer that
    /// when one is running.
    static func resolveBundleIdentifier() -> String {
        let running = NSWorkspace.shared.runningApplications

        if let pwa = running.first(where: { app in
            guard let id = app.bundleIdentifier else { return false }
            guard id.hasPrefix("com.google.Chrome.app.")
                || id.hasPrefix("com.microsoft.edgemac.app.")
                || id.hasPrefix("com.brave.Browser.app.") else { return false }
            return (app.localizedName ?? "").localizedCaseInsensitiveContains("YouTube Music")
        }), let id = pwa.bundleIdentifier {
            return id
        }

        let browsers = [
            "com.google.Chrome",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "com.google.Chrome.canary",
            "company.thebrowser.Browser",
            "com.vivaldi.Vivaldi",
        ]
        if let browser = browsers.first(where: { id in
            running.contains { $0.bundleIdentifier == id }
        }) {
            return browser
        }

        return "com.google.Chrome"
    }
}
