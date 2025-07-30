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
    
    var playbackStatePublisher: Published<PlaybackState>.Publisher { $playbackState }
    private var notificationObserver: Any?
    
    init() {
        setupPlaybackStateChangeObserver()
        Task {
            if isActive() {
                await updatePlaybackInfoAsync()
            }
        }
    }
    
    private func setupPlaybackStateChangeObserver() {
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task {
                await self?.updatePlaybackInfoAsync()
            }
        }
    }
    
    deinit {
        // Remove notification observer when controller is deallocated
        if let observer = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
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
        await updatePlaybackInfoAsync()
    }
    
    func toggleShuffle() async {
        await executeCommand("set shuffling to not shuffling")
        await updatePlaybackInfoAsync()
    }
    
    func toggleRepeat() async {
        await executeCommand("set repeating to not repeating")
        await updatePlaybackInfoAsync()
    }
    
    func isActive() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == playbackState.bundleIdentifier }
    }
    
    // MARK: - Private Methods
    
    // Public method for protocol conformance
    func updatePlaybackInfo() {
        Task {
            await updatePlaybackInfoAsync()
        }
    }
    
    private func updatePlaybackInfoAsync() async {
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard descriptor.numberOfItems >= 9 else { return }
        
        let isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        let currentTrack = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        let currentTrackArtist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        let currentTrackAlbum = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        let currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        let duration = (descriptor.atIndex(6)?.doubleValue ?? 0)/1000
        let isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let isRepeating = descriptor.atIndex(8)?.booleanValue ?? false
        let artworkURL = descriptor.atIndex(9)?.stringValue ?? ""
        
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
            lastUpdated: Date()
        )
        
        await MainActor.run {
            self.playbackState = state
        }
        
        // Load artwork asynchronously and update the state when complete
        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            let currentState = state
            Task.detached { [weak self] in
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    // Create a new state with the artwork data and update
                    var updatedState = currentState
                    updatedState.artwork = data
                    await MainActor.run {
                        self?.playbackState = updatedState
                    }
                } catch {
                    print("Failed to load artwork: \(error)")
                }
            }
        }
    }
    
    private func executeCommand(_ command: String) async {
        let script = "tell application \"Spotify\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
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
                set artworkURL to artwork url of current track
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatState, artworkURL}
            on error
                return {false, "Unknown", "Unknown", "Unknown", 0, 0, false, false, ""}
            end try
        end tell
        """
        
        return try await AppleScriptHelper.execute(script)
    }
}
