//
//  MusicManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import SwiftUI
import AVFoundation
import Combine



class MusicManager: ObservableObject {
    private var player = AVPlayer()
    private var playerItem: AVPlayerItem?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var songTitle: String = "Blinding Lights"
    @Published var artistName: String = "The Weeknd"
    @Published var albumArt: String = "music.note"
    @Published var isPlaying = false
    
    init() {
        setupNowPlayingObserver()
        setupPlaybackStateObserver()
    }
    
    private func setupNowPlayingObserver() {
        NotificationCenter.default.publisher(for: .AVPlayerItemNewAccessLogEntry, object: playerItem)
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)
    }
    
    private func setupPlaybackStateObserver() {
        player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                self?.isPlaying = (status == .playing)
            }
            .store(in: &cancellables)
    }
    
    private func updateNowPlayingInfo() {
        // Example: Get metadata from the currently playing AVPlayerItem
        guard let item = player.currentItem else { return }
        // 'commonMetadata' was deprecated in macOS 13.0: Use load(.commonMetadata) instead
        let metadataList = item.asset.commonMetadata
        
        
        print("Metadata: \(metadataList)")
        
        for metadata in metadataList {
            if metadata.commonKey?.rawValue == "title" {
                songTitle = metadata.stringValue ?? "Unknown Title"
            } else if metadata.commonKey?.rawValue == "artist" {
                artistName = metadata.stringValue ?? "Unknown Artist"
            } else if metadata.commonKey?.rawValue == "artwork",
                      // 'commonMetadata' was deprecated in macOS 13.0: Use load(.commonMetadata) instead
                      let data = metadata.dataValue,
                      let image = NSImage(data: data) {
                albumArt = image.name() ?? "music.note"
            }
        }
    }
    
    func togglePlayPause() {
        isPlaying ? player.pause() : player.play()
    }
    
    func nextTrack() {
        // Implement next track functionality
    }
    
    func previousTrack() {
        // Implement previous track functionality
    }
}
