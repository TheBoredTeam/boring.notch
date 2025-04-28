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
    
    func toggleShuffle() {
        executeCommand("set shuffle enabled to not shuffle enabled")
        updatePlaybackInfo()
    }
    
    func toggleRepeat() {
        executeCommand("""
            if song repeat is off then
                set song repeat to all
            else if song repeat is all then
                set song repeat to one
            else
                set song repeat to off
            end if
            """)
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
        let repeatModeValue = descriptor.atIndex(8)?.int32Value ?? 0
        let repeatMode = RepeatMode(rawValue: Int(repeatModeValue)) ?? .off
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
            repeatMode: repeatMode,
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
                set shuffleState to shuffle enabled
                set repeatState to song repeat
                if repeatState is off then
                    set repeatValue to 0
                else if repeatState is all then
                    set repeatValue to 1
                else if repeatState is one then
                    set repeatValue to 2
                end if

                try
                    set artData to data of artwork 1 of current track
                on error
                    set artData to ""
                end try
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatValue, artData}
            on error
                return {false, "Not Playing", "Unknown", "Unknown", 0, 0, false, 0, ""}
            end try
        end tell
        """
        
        return AppleScriptHelper.execute(script)
    }
}
