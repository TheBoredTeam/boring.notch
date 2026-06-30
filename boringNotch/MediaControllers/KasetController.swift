//
//  KasetController.swift
//  boringNotch
//
//  AppleScript-based controller for Kaset (https://github.com/sozercan/kaset),
//  a native macOS YouTube Music client. Modeled on AppleMusicController /
//  SpotifyController: it reads and controls Kaset through its AppleScript suite
//  (`get player info`, transport commands, `like track`). Favourite is supported
//  because Kaset exposes per-track like state, just like Apple Music's `favorited`.
//
//  Kaset's bundle id and AppleScript dictionary are fixed, so no configuration is
//  required. State is refreshed on a short poll and, when available, on Kaset's
//  `com.sertacozercan.Kaset.playerInfo` distributed notification.
//

import Combine
import Foundation
import SwiftUI

class KasetController: MediaControllerProtocol {
    // MARK: - Properties
    @Published private var playbackState = PlaybackState(
        bundleIdentifier: KasetController.bundleIdentifier
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool { true }
    var supportsFavorite: Bool { true }

    private static let bundleIdentifier = "com.sertacozercan.Kaset"
    private static let changeNotification = NSNotification.Name("com.sertacozercan.Kaset.playerInfo")
    private static let pollInterval: TimeInterval = 2.0

    private var notificationTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var artworkFetchTask: Task<Void, Never>?
    private var lastArtworkURL: String?

    // MARK: - Initialization
    init() {
        setupPlaybackStateChangeObserver()
        startPolling()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }

    deinit {
        notificationTask?.cancel()
        artworkFetchTask?.cancel()
        pollTimer?.invalidate()
    }

    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: KasetController.changeNotification
            )
            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        // Kaset is sandboxed; its distributed notification may not be delivered on
        // every system, so poll as a reliable baseline (the notification just makes
        // updates snappier when it does arrive).
        pollTimer = Timer.scheduledTimer(withTimeInterval: KasetController.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Call unconditionally: updatePlaybackInfo handles the inactive case
                // (it clears state), so this is how we notice Kaset quitting.
                await self.updatePlaybackInfo()
            }
        }
    }

    // MARK: - Protocol Implementation
    func play() async { await executeCommand("play") }
    func pause() async { await executeCommand("pause") }
    func togglePlay() async { await executeCommand("playpause") }
    func nextTrack() async { await executeCommand("next track") }
    func previousTrack() async { await executeCommand("previous track") }

    func seek(to time: Double) async {
        await executeCommand("seek \(time)")
        await refreshSoon()
    }

    func toggleShuffle() async {
        await executeCommand("toggle shuffle")
        await refreshSoon()
    }

    func toggleRepeat() async {
        await executeCommand("cycle repeat")
        await refreshSoon()
    }

    func setVolume(_ level: Double) async {
        let percentage = Int((max(0.0, min(1.0, level)) * 100).rounded())
        await executeCommand("set volume \(percentage)")
        await refreshSoon()
    }

    @MainActor
    func setFavorite(_ favorite: Bool) async {
        // Kaset's `like track` toggles; only send it when the state actually flips.
        // @MainActor-isolated so this `isFavorite` read shares the isolation domain
        // that writes playbackState (applyPlayerInfo), avoiding a data race.
        guard favorite != playbackState.isFavorite else { return }
        await executeCommand("like track")
        await refreshSoon()
    }

    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == KasetController.bundleIdentifier
        }
    }

    func updatePlaybackInfo() async {
        guard isActive() else {
            // Kaset isn't running; clear any stale track so the notch doesn't keep
            // showing a phantom Kaset song after the app quits.
            await resetPlaybackState()
            return
        }
        guard let descriptor = try? await AppleScriptHelper.execute(
                  "tell application \"Kaset\" to get player info"
              ),
              let json = descriptor.stringValue,
              let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        await applyPlayerInfo(object)
    }

    // MARK: - Private Methods

    // Main-actor isolated so the poll timer and the distributed-notification
    // observer (which run on different executors) can't mutate state concurrently.
    @MainActor
    private func applyPlayerInfo(_ object: [String: Any]) {
        var state = playbackState

        let track = object["currentTrack"] as? [String: Any]
        state.isPlaying = (object["isPlaying"] as? Bool) ?? false
        state.title = (track?["name"] as? String) ?? "Not Playing"
        state.artist = (track?["artist"] as? String) ?? ""
        state.album = (track?["album"] as? String) ?? ""
        state.currentTime = Self.double(object["position"]) ?? 0
        state.duration = Self.double(object["duration"]) ?? Self.double(track?["duration"]) ?? 0
        state.isShuffled = (object["shuffling"] as? Bool) ?? false
        state.repeatMode = Self.repeatMode(object["repeating"] as? String)
        if let volume = Self.double(object["volume"]) { state.volume = volume / 100.0 }
        state.isFavorite = (object["likeStatus"] as? String) == "liked"
        state.lastUpdated = Date()

        if state != playbackState {
            playbackState = state
        }

        fetchArtworkIfNeeded(urlString: track?["artworkURL"] as? String)
    }

    @MainActor
    private func fetchArtworkIfNeeded(urlString: String?) {
        guard let urlString, !urlString.isEmpty, urlString != lastArtworkURL,
              let url = URL(string: urlString) else { return }
        lastArtworkURL = urlString
        artworkFetchTask?.cancel()
        artworkFetchTask = Task { [weak self] in
            guard let data = try? await ImageService.shared.fetchImageData(from: url) else { return }
            await MainActor.run { [weak self] in
                self?.playbackState.artwork = data
            }
        }
    }

    @MainActor
    private func resetPlaybackState() {
        artworkFetchTask?.cancel()
        lastArtworkURL = nil
        let cleared = PlaybackState(bundleIdentifier: KasetController.bundleIdentifier, isPlaying: false)
        if cleared != playbackState {
            playbackState = cleared
        }
    }

    private func executeCommand(_ command: String) async {
        try? await AppleScriptHelper.executeVoid("tell application \"Kaset\" to \(command)")
    }

    private func refreshSoon() async {
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func repeatMode(_ value: String?) -> RepeatMode {
        switch value {
        case "all": .all
        case "one": .one
        default: .off
        }
    }
}
