//
//  AppleMusicController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class AppleMusicController: MediaControllerProtocol {
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: MediaAppBundleID.appleMusic,
        playbackRate: 1
    )
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        return true
    }

    var supportsFavorite: Bool { capabilities.favorite }
    var capabilities: MediaCapabilities { playbackState.capabilities ?? .unsupported }
    private var updateGeneration = 0

    private var notificationTask: Task<Void, Never>?
    
    // MARK: - Initialization
    init() {
        setupPlaybackStateChangeObserver()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }
    
    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            for await _ in AppleScriptControllerSupport.playerInfoNotifications(named: "com.apple.Music.playerInfo") {
                await self?.updatePlaybackInfo()
            }
        }
    }
    
    deinit {
        notificationTask?.cancel()
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
        guard PlaybackTime.valid(time), let range = PlaybackTime.seekRange(duration: playbackState.duration), range.contains(time) else { return }
        await executeCommand("set player position to \(time)")
        await updatePlaybackInfo()
    }
    
    func toggleShuffle() async {
        guard capabilities.shuffle else { return }
        await executeCommand("set shuffle enabled to not shuffle enabled")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func toggleRepeat() async {
        guard capabilities.repeatModes.count > 1 else { return }
        await executeCommand("""
            if song repeat is off then
                set song repeat to all
            else if song repeat is all then
                set song repeat to one
            else
                set song repeat to off
            end if
            """)
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func setVolume(_ level: Double) async {
        guard level.isFinite else { return }
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        await executeCommand("set sound volume to \(volumePercentage)")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func isActive() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == MediaAppBundleID.appleMusic }
    }

    func setFavorite(_ favorite: Bool) async {
        guard supportsFavorite else { return }
        let script = """
        tell application "Music"
            try
                set favorited of current track to \(favorite)
            end try
        end tell
        """
        try? await AppleScriptHelper.executeVoid(script)
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func updatePlaybackInfo() async {
        updateGeneration += 1
        let generation = updateGeneration
        guard let descriptor = try? await fetchPlaybackInfoAsync(), generation == updateGeneration else { return }
        guard descriptor.numberOfItems >= 11 else { return }
        var updatedState = PlaybackState(bundleIdentifier: MediaAppBundleID.appleMusic)
        updatedState.capabilities = descriptor.numberOfItems >= 13
            ? MediaCapabilities(favorite: descriptor.atIndex(12)?.booleanValue ?? false, shuffle: true, repeatModes: [.off, .all, .one])
            : .unsupported
        updatedState.trackIdentifier = descriptor.atIndex(13)?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        
        updatedState.isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        updatedState.title = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        updatedState.artist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        updatedState.album = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        updatedState.currentTime = PlaybackTime.sanitized(descriptor.atIndex(5)?.doubleValue ?? 0)
        updatedState.duration = PlaybackTime.sanitized(descriptor.atIndex(6)?.doubleValue ?? 0)
        updatedState.isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let repeatModeValue = descriptor.atIndex(8)?.int32Value ?? 0
        updatedState.repeatMode = RepeatMode(rawValue: Int(repeatModeValue)) ?? .off
        let volumePercentage = descriptor.atIndex(9)?.int32Value ?? 50
        updatedState.volume = Double(volumePercentage) / 100.0
        updatedState.artwork = descriptor.atIndex(10).flatMap { $0.stringValue == "" ? nil : $0.data }
        let lovedState = descriptor.atIndex(11)?.booleanValue ?? false
        updatedState.isFavorite = lovedState
        updatedState.lastUpdated = Date()
        self.playbackState = updatedState
    }
    
    // MARK: - Private Methods
    
    private func executeCommand(_ command: String) async {
        await AppleScriptControllerSupport.executeCommand(command, appName: "Music")
    }
    
    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Music"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to 0
                try
                    set trackDuration to duration of current track
                end try
                set shuffleState to shuffle enabled
                set repeatState to song repeat
                if repeatState is off then
                    set repeatValue to 1
                else if repeatState is one then
                    set repeatValue to 2
                else if repeatState is all then
                    set repeatValue to 3
                end if

                try
                    set artData to data of artwork 1 of current track
                on error
                    set artData to ""
                end try
                
                set currentVolume to sound volume
                set favoriteState to false
                set favoriteAvailable to false
                try
                    set favoriteState to favorited of current track
                    set favoriteAvailable to true
                end try
                set trackID to ""
                try
                    set trackID to persistent ID of current track
                end try
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatValue, currentVolume, artData, favoriteState, favoriteAvailable, trackID}
            on error
                return {false, "Not Playing", "Unknown", "Unknown", 0, 0, false, 0, 50, "", false}
            end try
        end tell
        """
        
        return try await AppleScriptHelper.execute(script)
    }
    
}
