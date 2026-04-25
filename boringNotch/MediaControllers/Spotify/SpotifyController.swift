//
//  SpotifyController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import Combine
import SwiftUI

final class SpotifyController: MediaControllerProtocol {

    // MARK: - Types
    typealias NetworkAccessEvaluator = @Sendable () async -> Bool

    // MARK: - Properties
    @Published private var playbackState = PlaybackState(
        bundleIdentifier: "com.spotify.client"
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool { true }

    var supportsFavorite: Bool {
        guard webApiProvider != nil else { return appleScriptProvider.supportsFavorite }
        let keychain = SpotifyKeychainManager.shared
        let isAvailable = keychain.isTokenValid || keychain.refreshToken != nil
        return isAvailable
    }

    private let appleScriptProvider: SpotifyProvider
    private let webApiProvider: SpotifyProvider?
    private let hasNetworkAccess: NetworkAccessEvaluator

    private var notificationTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var artworkFetchTask: Task<Void, Never>?
    private var lastArtworkURL: String?
    private let commandUpdateDelay: Duration = .milliseconds(25)
    private let pollingInterval: Duration = .seconds(1)

    // MARK: - Initialization
    init(
        appleScriptProvider: SpotifyProvider = SpotifyAppleScriptProvider(),
        webApiProvider: SpotifyProvider? = nil,
        hasNetworkAccess: @escaping NetworkAccessEvaluator = {
            await SpotifyAuthManager.shared.validToken() != nil
        }
    ) {
        self.appleScriptProvider = appleScriptProvider
        self.webApiProvider = webApiProvider
        self.hasNetworkAccess = hasNetworkAccess

        setupPlaybackStateChangeObserver()
        startPolling()

        Task { [weak self] in
            guard let self, self.isActive() else { return }
            await self.updatePlaybackInfo()
        }
    }

    deinit {
        notificationTask?.cancel()
        pollingTask?.cancel()
        artworkFetchTask?.cancel()
    }

    // MARK: - MediaControllerProtocol
    func setFavorite(_ favorite: Bool) async {
        guard let trackID = await currentTrackIDForFavoriteAction() else { return }
        await getPlaybackProvider().setLiked(favorite, id: trackID)
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }

    func play() async {
        await getPlaybackProvider().play()
    }

    func pause() async {
        await getPlaybackProvider().pause()
    }

    func togglePlay() async {
        await getPlaybackProvider().togglePlay()
    }

    func nextTrack() async {
        await getPlaybackProvider().nextTrack()
    }

    func previousTrack() async {
        let provider = await getPlaybackProvider()
        await provider.previousTrack()
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }

    func seek(to time: Double) async {
        let provider = await getPlaybackProvider()
        await provider.seek(to: time)
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }

    func toggleShuffle() async {
        let provider = await getPlaybackProvider()
        await provider.setShuffle(!playbackState.isShuffled)
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }

    func toggleRepeat() async {
        let provider = await getPlaybackProvider()
        await provider.setRepeat(playbackState.repeatMode == .off)
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }

    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)

        let provider = await getPlaybackProvider()
        await provider.setVolume(volumePercentage)
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }

    nonisolated func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
    }

    func updatePlaybackInfo() async {
        let provider = await getPlaybackProvider()
        let playerState = await provider.getPlayerState()

        var state = PlaybackState(
            bundleIdentifier: "com.spotify.client",
            isPlaying: playerState.isPlaying,
            title: playerState.trackName,
            artist: playerState.artist,
            album: playerState.album,
            currentTime: playerState.position,
            duration: playerState.duration,
            playbackRate: 1,
            isShuffled: playerState.shuffle,
            repeatMode: playerState.repeat ? .all : .off,
            lastUpdated: Date(),
            artwork: nil,
            volume: Double(playerState.volume) / 100.0,
            isFavorite: playerState.isLiked
        )

        if playerState.artworkURL == lastArtworkURL, let existingArtwork = playbackState.artwork {
            state.artwork = existingArtwork
        }

        playbackState = state

        guard !playerState.artworkURL.isEmpty, let url = URL(string: playerState.artworkURL) else {
            return
        }

        guard playerState.artworkURL != lastArtworkURL || state.artwork == nil else {
            return
        }

        artworkFetchTask?.cancel()

        let currentState = state
        let artworkURL = playerState.artworkURL

        artworkFetchTask = Task { [weak self] in
            do {
                let data = try await ImageService.shared.fetchImageData(from: url)
                guard let self else { return }

                var updatedState = currentState
                updatedState.artwork = data
                self.playbackState = updatedState
                self.lastArtworkURL = artworkURL
                self.artworkFetchTask = nil
            } catch {
                guard let self else { return }
                self.artworkFetchTask = nil
            }
        }
    }

    // MARK: - Private Methods
    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.spotify.client.PlaybackStateChanged")
            )

            for await _ in notifications {
                guard let self else { return }
                await self.updatePlaybackInfo()
            }
        }
    }
    
    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: self.pollingInterval)
                guard self.isActive() else { continue }
                await self.updatePlaybackInfo()
            }
        }
    }

    private func getPlaybackProvider() async -> SpotifyProvider {
        let hasAccess = await hasNetworkAccess()
        guard let webApiProvider, hasAccess else {
            return appleScriptProvider
        }

        return webApiProvider
    }

    private func currentTrackIDForFavoriteAction() async -> String? {
        let provider = await getPlaybackProvider()
        let playerState = await provider.getPlayerState()
        return playerState.trackID.isEmpty ? nil : playerState.trackID
    }
}
