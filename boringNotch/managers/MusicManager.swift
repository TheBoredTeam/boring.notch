//
//  PlaybackManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on  04/08/24.
//


import SwiftUI
import Combine
import AppKit

var defaultImage: NSImage = NSImage(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    private var currentWorkItem: DispatchWorkItem?
    private var vm: BoringViewModel
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    var albumArtData: Data?
    @Published var isPlaying = false
    @Published var musicToggledManually: Bool = false
    @Published var album: String = "Self Love"
    @Published var playbackManager = PlaybackManager()
    @Published var lastUpdated: Date = Date()
    @Published var isPlayerIdle: Bool = true
    @Published var animations: BoringAnimations = BoringAnimations()
    @Published var avgColor: NSColor = .white

    private var debounceToggle: DispatchWorkItem?

    init(vm: BoringViewModel) {
        self.vm = vm
        setupNowPlayingObserver()
        fetchNowPlayingInfo()
    }

    private func setupNowPlayingObserver() {
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchNowPlayingInfo()
            }
            .store(in: &cancellables)

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchNowPlayingInfo()
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchNowPlayingInfo()
        }
    }

    @objc func fetchNowPlayingInfo(bypass: Bool = false) {
        if musicToggledManually {
            return
        }

        // Load framework
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")) else { return }

        // Get a Swift function for MRMediaRemoteGetNowPlayingInfo
        guard let MRMediaRemoteGetNowPlayingInfoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) else { return }
        typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
        let MRMediaRemoteGetNowPlayingInfo = unsafeBitCast(MRMediaRemoteGetNowPlayingInfoPointer, to: MRMediaRemoteGetNowPlayingInfoFunction.self)

        // Get song info
        MRMediaRemoteGetNowPlayingInfo(DispatchQueue.main) { [weak self] information in
            guard let self = self else { return }
            
            // Check if the song is paused
            if let state = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Int {
                if !self.isPlaying && state == 0 {
                    return
                }
                self.musicIsPaused(state: state == 1, setIdle: true)
            } else {
                self.musicIsPaused(state: false, setIdle: false)
            }

            let albumArtData: Data? = information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
            if albumArtData == nil {
                return
            }

            // Check if the song is same as the previous one
            if let title = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
               title == self.songTitle && albumArtData == nil {
                return
            } else if albumArtData == self.albumArtData {
                return
            }

            if let artist = information["kMRMediaRemoteNowPlayingInfoArtist"] as? String {
                self.artistName = artist
            }

            if let title = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String {
                self.songTitle = title
            }

            if let album = information["kMRMediaRemoteNowPlayingInfoAlbum"] as? String {
                self.album = album
            }

            if albumArtData != nil,
               let artworkImage = NSImage(data: albumArtData!) {
                self.albumArtData = albumArtData
                self.updateAlbumArt(newAlbumArt: artworkImage)
            }
        }
    }

    func musicIsPaused(state: Bool, bypass: Bool = false, setIdle: Bool = false) {
        if self.musicToggledManually && !bypass {
            return
        }

        withAnimation {
            self.isPlaying = state
            self.playbackManager.isPlaying = state

            DispatchQueue.main.asyncAfter(deadline: .now() + self.vm.waitInterval) {
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    func togglePlayPause() {
        debounceToggle?.cancel()

        debounceToggle = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.musicToggledManually = true
            let playState: Bool = self.playbackManager.playPause()
            self.musicIsPaused(state: playState, bypass: true, setIdle: true)

            if playState {
                self.fetchNowPlayingInfo(bypass: true)
            } else {
                self.lastUpdated = Date()
            }

            // Reset the manual toggle flag after 1 second
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.musicToggledManually = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: debounceToggle!)
    }

    func updateAlbumArt(newAlbumArt: NSImage) {
        withAnimation(vm.animation) {
            self.albumArt = newAlbumArt
            if vm.coloredSpectrogram {
                self.calculateAverageColor()
            }
        }
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                self?.avgColor = color ?? .white
            }
        }
    }

    func nextTrack() {
        playbackManager.nextTrack()
        fetchNowPlayingInfo(bypass: true)
    }

    func previousTrack() {
        playbackManager.previousTrack()
        fetchNowPlayingInfo(bypass: true)
    }
}
