//
//  KairoMusicBridge.swift
//  Kairo
//
//  Bridges the MusicManager to Kairo's backend.
//  Sends now-playing updates via WebSocket so the AI brain
//  knows what's currently playing.
//

import AppKit
import Combine
import Foundation

@MainActor
class KairoMusicBridge: ObservableObject {
    static let shared = KairoMusicBridge()

    private var cancellables = Set<AnyCancellable>()
    private var lastReportedTrack: String = ""

    func startBridging() {
        let music = MusicManager.shared

        Publishers.CombineLatest3(
            music.$songTitle,
            music.$artistName,
            music.$isPlaying
        )
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] title, artist, playing in
            self?.reportNowPlaying(title: title, artist: artist, playing: playing)
        }
        .store(in: &cancellables)
    }

    private func reportNowPlaying(title: String, artist: String, playing: Bool) {
        let trackKey = "\(title)|\(artist)|\(playing)"
        guard trackKey != lastReportedTrack else { return }
        lastReportedTrack = trackKey
        guard !title.isEmpty, title != "Nothing Playing" else { return }

        let music = MusicManager.shared
        let payload: [String: Any] = [
            "type": "now_playing_update",
            "title": title,
            "artist": artist,
            "album": music.album,
            "is_playing": playing,
            "duration": music.songDuration,
            "elapsed": music.elapsedTime,
            "bundle_id": music.bundleIdentifier ?? "",
            "platform": platformName(music.bundleIdentifier),
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let text = String(data: data, encoding: .utf8) {
            KairoSocket.shared.sendRaw(text)
        }
    }

    nonisolated private func platformName(_ bundleID: String?) -> String {
        switch bundleID {
        case "com.spotify.client": return "Spotify"
        case "com.apple.Music": return "Apple Music"
        case "com.google.Chrome": return "YouTube"
        case "com.apple.Safari": return "Safari"
        case "com.apple.podcasts": return "Podcasts"
        default: return "Music"
        }
    }
}
