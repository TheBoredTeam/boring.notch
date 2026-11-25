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

    var supportsFavorite: Bool {
        return true
    }

    private var notificationTask: Task<Void, Never>?

    /// Artwork looked up online for tracks whose artwork isn't scriptable (streamed Apple Music tracks).
    private var fallbackArtworkKey: String?
    private var fallbackArtwork: Data?
    private var fallbackArtworkTask: Task<Void, Never>?

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
        await executeCommand("set player position to \(time)")
        await updatePlaybackInfo()
    }

    func toggleShuffle() async {
        await executeCommand("set shuffle enabled to not shuffle enabled")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    func toggleRepeat() async {
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
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard descriptor.numberOfItems >= 11 else { return }
        var updatedState = self.playbackState

        updatedState.isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        updatedState.title = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        updatedState.artist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        updatedState.album = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        updatedState.currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        updatedState.duration = descriptor.atIndex(6)?.doubleValue ?? 0
        updatedState.isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let repeatModeValue = descriptor.atIndex(8)?.int32Value ?? 0
        updatedState.repeatMode = RepeatMode(rawValue: Int(repeatModeValue)) ?? .off
        let volumePercentage = descriptor.atIndex(9)?.int32Value ?? 50
        updatedState.volume = Double(volumePercentage) / 100.0
        updatedState.artwork = Self.imageData(from: descriptor.atIndex(10))
        let lovedState = descriptor.atIndex(11)?.booleanValue ?? false
        updatedState.isFavorite = lovedState
        updatedState.lastUpdated = Date()
        if updatedState.artwork == nil {
            updatedState.artwork = fallbackArtwork(for: updatedState)
        }
        self.playbackState = updatedState
    }

    /// The script returns "" when a track has no artwork; only keep real image payloads.
    private static func imageData(from descriptor: NSAppleEventDescriptor?) -> Data? {
        guard let descriptor, descriptor.descriptorType != typeUnicodeText,
              descriptor.descriptorType != typeUTF8Text else { return nil }
        let data = descriptor.data
        return data.isEmpty || NSImage(data: data) == nil ? nil : data
    }

    /// Streamed Apple Music tracks expose no scriptable artwork on macOS 26, so look the
    /// album up in the iTunes Search API. Returns cached artwork for the current album, or
    /// starts a lookup and publishes the result when it arrives.
    private func fallbackArtwork(for state: PlaybackState) -> Data? {
        guard let key = Self.fallbackArtworkKey(for: state) else { return nil }
        if key == fallbackArtworkKey { return fallbackArtwork }

        fallbackArtworkKey = key
        fallbackArtwork = nil
        fallbackArtworkTask?.cancel()
        let album = state.album == "Unknown" ? "" : state.album
        fallbackArtworkTask = Task { [weak self] in
            let result: Data?
            do {
                result = try await Self.lookUpArtwork(artist: state.artist, album: album, title: state.title)
            } catch {
                // Network failure: forget the key so a later update retries. A lookup that
                // simply finds nothing stays cached, so we don't query again on every poll.
                if let self, !Task.isCancelled, self.fallbackArtworkKey == key {
                    self.fallbackArtworkKey = nil
                }
                return
            }
            guard let data = result, !Task.isCancelled, let self, self.fallbackArtworkKey == key else { return }
            self.fallbackArtwork = data
            // Only the album has to match: skipping to another track on the same album
            // while the lookup is in flight should still get the artwork.
            var current = self.playbackState
            guard current.artwork == nil, Self.fallbackArtworkKey(for: current) == key else { return }
            current.artwork = data
            self.playbackState = current
        }
        return nil
    }

    /// Identifies the artwork to look up: the album, or the track when there is no album.
    private static func fallbackArtworkKey(for state: PlaybackState) -> String? {
        guard state.title != "Not Playing", !state.artist.isEmpty, state.artist != "Unknown" else { return nil }
        let album = state.album == "Unknown" ? "" : state.album
        return "\(state.artist)|\(album.isEmpty ? state.title : album)"
    }

    /// Returns the artwork, nil when nothing matching was found, or throws on a network error.
    private nonisolated static func lookUpArtwork(artist: String, album: String, title: String) async throws -> Data? {
        let entity = album.isEmpty ? "song" : "album"
        let name = album.isEmpty ? title : album
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(name)"),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components?.url else { return nil }
        let searchData = try await ImageService.shared.fetchImageData(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }

        // The search is fuzzy: only accept a result whose artist and album (or track) match.
        let nameField = album.isEmpty ? "trackName" : "collectionName"
        guard let match = results.first(where: { result in
                  matches(result["artistName"] as? String, artist) && matches(result[nameField] as? String, name)
              }),
              let small = match["artworkUrl100"] as? String,
              let artworkURL = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
        else { return nil }

        let artwork = try await ImageService.shared.fetchImageData(from: artworkURL)
        return NSImage(data: artwork) == nil ? nil : artwork
    }

    /// Loose comparison that tolerates case, accents, and suffixes such as
    /// "(Deluxe Edition)" or " - Single" on either side.
    private nonisolated static func matches(_ candidate: String?, _ expected: String) -> Bool {
        guard let candidate else { return false }
        let normalize = { (string: String) in
            string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let a = normalize(candidate), b = normalize(expected)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.hasPrefix(b) || b.hasPrefix(a)
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
                set trackDuration to duration of current track
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
                set favoriteState to favorited of current track
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatValue, currentVolume, artData, favoriteState}
            on error
                return {false, "Not Playing", "Unknown", "Unknown", 0, 0, false, 0, 50, "", false}
            end try
        end tell
        """

        return try await AppleScriptHelper.execute(script)
    }
}
