//
//  AppleMusicController.swift
//  boringNotch
//
//  Created by Alexander Greco on 2025-03-29.
//

import Foundation
import Combine
import SwiftUI

class AppleMusicController: MediaControllerProtocol {
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.apple.Music"
    )
    
    var playbackStatePublisher: Published<PlaybackState>.Publisher { $playbackState }
    
    // MARK: - Initialization
    init() {
        setupPlaybackStateChangeObserver()
        updatePlaybackInfo()
    }
    
    private func setupPlaybackStateChangeObserver() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(updatePlaybackInfo),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name("com.apple.Music.playerInfo"),
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
        guard descriptor.numberOfItems >= 8 else { return }
        
        let isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        let currentTrack = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        let currentTrackArtist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        let currentTrackAlbum = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        let currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        let duration = descriptor.atIndex(6)?.doubleValue ?? 0
        let isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let isRepeating = descriptor.atIndex(8)?.booleanValue ?? false
        let artworkData = descriptor.atIndex(9)?.data as Data?
        
        let updatedState = PlaybackState(
            bundleIdentifier: "com.apple.Music",
            isPlaying: isPlaying,
            title: currentTrack,
            artist: currentTrackArtist,
            album: currentTrackAlbum,
            currentTime: currentTime,
            duration: duration,
            playbackRate: 1,
            isShuffled: isShuffled,
            isRepeating: isRepeating,
            lastUpdated: Date(),
            artwork: (artworkData?.isEmpty ?? true) ? nil : artworkData
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.playbackState = updatedState
        }
    }
    
    private func executeCommand(_ command: String) {
        let script = "tell application \"Music\" to \(command)"
        AppleScriptHelper.executeVoid(script)
    }
    
    private func fetchPlaybackInfo() -> NSAppleEventDescriptor? {
        let script = """
        tell application "Music"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to false
                set repeatState to false
                try
                    set artData to data of artwork 1 of current track
                on error
                    set artData to ""
                end try
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatState, artData}
            on error
                return {false, "Not Playing", "Unknown", "Unknown", 0, 0, false, false, ""}
            end try
        end tell
        """
        
        return AppleScriptHelper.execute(script)
    }
}
