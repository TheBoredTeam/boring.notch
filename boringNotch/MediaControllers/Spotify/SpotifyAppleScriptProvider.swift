//
//  SpotifyAppleScriptProvider.swift
//  boringNotch
//
//  Created by Dan on 4/15/26.
//

import Foundation

final class SpotifyAppleScriptProvider: SpotifyProvider {

    // MARK: - Properties
    let supportsFavorite: Bool = false

    // MARK: - SpotifyProvider
    func getPlayerState() async -> SpotifyPlayerState {
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

        guard let result = try? await AppleScriptHelper.execute(script) else {
            return SpotifyPlayerState()
        }

        return SpotifyPlayerState(
            isPlaying: result.atIndex(1)?.booleanValue ?? false,
            trackName: result.atIndex(2)?.stringValue ?? "Unknown",
            artist: result.atIndex(3)?.stringValue ?? "Unknown",
            album: result.atIndex(4)?.stringValue ?? "Unknown",
            position: result.atIndex(5)?.doubleValue ?? 0,
            duration: (result.atIndex(6)?.doubleValue ?? 0) / 1000,
            trackID: "",
            shuffle: result.atIndex(7)?.booleanValue ?? false,
            repeat: result.atIndex(8)?.booleanValue ?? false,
            volume: Int(result.atIndex(9)?.int32Value ?? 50),
            artworkURL: result.atIndex(10)?.stringValue ?? "",
            isLiked: false
        )
    }

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
    }

    func setVolume(_ volume: Int) async {
        let clampedVolume = max(0, min(100, volume))
        await executeCommand("set sound volume to \(clampedVolume)")
    }

    func setShuffle(_ enabled: Bool) async {
        await executeCommand("set shuffling to \(enabled)")
    }

    func setRepeat(_ enabled: Bool) async {
        await executeCommand("set repeating to \(enabled)")
    }

    func isTrackLiked(id: String) async -> Bool {
        false
    }

    func setLiked(_ liked: Bool, id: String) async {
        guard liked else { return }
        await executeCommand("like track")
    }

    // MARK: - Private Helpers
    private func executeCommand(_ command: String) async {
        let script = "tell application \"Spotify\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }
}
