//
//  SpotifyController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import Combine
import SwiftUI

class SpotifyController: MediaControllerProtocol {
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.spotify.client"
    )
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }
    
    private var notificationTask: Task<Void, Never>?
    private var volumeMonitorTask: Task<Void, Never>?
    
    //Constant for time between command and update
    let commandUpdateDelay: Duration = .milliseconds(25)
    
    init() {
        setupPlaybackStateChangeObserver()
        Task {
            if isActive() {
                await updatePlaybackInfo()
                await startVolumeMonitoring()
            }
        }
    }
    
    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.spotify.client.PlaybackStateChanged")
            )
            
            for await _ in notifications {
                await self?.updatePlaybackInfo()
                if self?.isActive() == true {
                    await self?.startVolumeMonitoring()
                }
            }
        }
    }
    
    deinit {
        notificationTask?.cancel()
        volumeMonitorTask?.cancel()
    }
    
    // MARK: - Protocol Implementation
    func play() async {
        await executeCommand("play")
    }
    
    func pause() async {
        await executeCommand("pause")
    }
    
    func togglePlay() async {
        await executeCommand("playpause")
    }
    
    func nextTrack() async {
        await executeCommand("next track")
    }
    
    func previousTrack() async {
        await executeCommand("previous track")
    }
    
    func seek(to time: Double) async {
        await executeCommand("set player position to \(time)")
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    func toggleShuffle() async {
        await executeCommand("set shuffling to not shuffling")
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    func toggleRepeat() async {
        await executeCommand("set repeating to not repeating")
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        await executeCommand("set sound volume to \(volumePercentage)")
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    func isActive() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == playbackState.bundleIdentifier }
    }
    
    func updatePlaybackInfo() async {
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard descriptor.numberOfItems >= 10 else { return }
        
        let isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        let currentTrack = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        let currentTrackArtist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        let currentTrackAlbum = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        let currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        let duration = (descriptor.atIndex(6)?.doubleValue ?? 0)/1000
        let isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let isRepeating = descriptor.atIndex(8)?.booleanValue ?? false
        let volumePercentage = descriptor.atIndex(9)?.int32Value ?? 50
        let artworkURL = descriptor.atIndex(10)?.stringValue ?? ""
        
        let state = PlaybackState(
            bundleIdentifier: "com.spotify.client",
            isPlaying: isPlaying,
            title: currentTrack,
            artist: currentTrackArtist,
            album: currentTrackAlbum,
            currentTime: currentTime,
            duration: duration,
            playbackRate: 1,
            isShuffled: isShuffled,
            repeatMode: isRepeating ? .all : .off,
            lastUpdated: Date(),
            artwork: nil,
            volume: Double(volumePercentage) / 100.0
        )
        
        self.playbackState = state
        
        // Load artwork asynchronously and update the state when complete
        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            let currentState = state
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                // Create a new state with the artwork data and update
                var updatedState = currentState
                updatedState.artwork = data
                playbackState = updatedState
            } catch {
                print("Failed to load artwork: \(error)")
            }
        }
    }
    
// MARK: - Private Methods
    
    private func executeCommand(_ command: String) async {
        let script = "tell application \"Spotify\" to \(command)"
        do {
            try await AppleScriptHelper.executeVoid(script)
        } catch {
            // Silently handle error
        }
    }
    
    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Spotify"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to shuffling
                set repeatState to repeating
                set currentVolume to sound volume
                set artworkURL to artwork url of current track
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatState, currentVolume, artworkURL}
            on error
                return {false, "Unknown", "Unknown", "Unknown", 0, 0, false, false, 50, ""}
            end try
        end tell
        """
        
        return try await AppleScriptHelper.execute(script)
    }
    
    private func startVolumeMonitoring() async {
        volumeMonitorTask?.cancel()
        volumeMonitorTask = Task { [weak self] in
            while !Task.isCancelled && self?.isActive() == true {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled {
                    await self?.checkVolumeChange()
                }
            }
        }
    }
    
    private func checkVolumeChange() async {
        guard let volumeScript = try? await AppleScriptHelper.execute(
            "tell application \"Spotify\" to get sound volume"
        ) else { return }
        
        let volumeValue = volumeScript.int32Value
        let currentVolume = Double(volumeValue) / 100.0
        if abs(currentVolume - playbackState.volume) > 0.01 {
            var updatedState = playbackState
            updatedState.volume = currentVolume
            updatedState.lastUpdated = Date()
            self.playbackState = updatedState
        }
    }
}
