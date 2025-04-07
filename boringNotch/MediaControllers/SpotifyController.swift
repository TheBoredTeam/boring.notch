//
//  SpotifyController.swift
//  boringNotch
//
//  Created by Alexander Greco on 2025-03-29.
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
    
    init() {
        setupPlaybackStateChangeObserver()
        updatePlaybackInfo()
    }
    
    private func setupPlaybackStateChangeObserver() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(updatePlaybackInfo),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
    }
    
    deinit {
        // Remove notification observer when controller is deallocated
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
    }
    
    // MARK: - Protocol Implementation
    func play() {
        executeCommand("play")
    }
    
    func pause() {
        executeCommand("pause")
    }
    
    func togglePlay() {
        executeCommand("playpause")
    }
    
    func nextTrack() {
        executeCommand("next track")
    }
    
    func previousTrack() {
        executeCommand("previous track")
    }
    
    func seek(to time: Double) {
        executeCommand("set player position to \(time)")
        updatePlaybackInfo()
    }
    
    func isActive() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == playbackState.bundleIdentifier }
    }
    
    // MARK: - Private Methods
    @objc func updatePlaybackInfo() {
        guard let descriptor = fetchPlaybackInfo() else { return }
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
            isRepeating: isRepeating,
            lastUpdated: Date()
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.playbackState = state
        }
        
        // Load artwork asynchronously and update the state when complete
        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            DispatchQueue.global(qos: .background).async { [weak self] in
                do {
                    let artworkData = try Data(contentsOf: url)
                    DispatchQueue.main.async {
                        // Create a new state with the artwork data and update
                        var updatedState = state
                        updatedState.artwork = artworkData
                        self?.playbackState = updatedState
                    }
                } catch {
                    print("Failed to load artwork: \(error)")
                }
            }
        }
    }
    
    private func executeCommand(_ command: String) {
        let script = "tell application \"Spotify\" to \(command)"
        AppleScriptHelper.executeVoid(script)
    }
    
    private func fetchPlaybackInfo() -> NSAppleEventDescriptor? {
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
        
        return AppleScriptHelper.execute(script)
    }
}
