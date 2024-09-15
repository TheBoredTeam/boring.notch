    //
    //  MusicManager.swift
    //  boringNotch
    //
    //  Created by Harsh Vardhan  Goswami  on 03/08/24.
    //
import AppKit
import Combine
import SwiftUI

var defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    private var debounceToggle: DispatchWorkItem?
    private var vm: BoringViewModel
    private var lastMusicItem: (title: String, artist: String, album: String, artworkData: Data?)?
    private var isCurrentlyPlaying: Bool = false
    
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var musicToggledManually: Bool = false
    @Published var album: String = "Self Love"
    @Published var playbackManager = PlaybackManager()
    @Published var lastUpdated: Date = .init()
    @Published var isPlayerIdle: Bool = true
    @Published var animations: BoringAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String = "com.apple.Music"
    @ObservedObject var detector: FullscreenMediaDetector
    var nowPlaying: NowPlaying
    
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteGetNowPlayingInfo: @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private let MRMediaRemoteRegisterForNowPlayingNotifications: @convention(c) (DispatchQueue) -> Void
    
    init?(vm: BoringViewModel) {
        self.vm = vm
        
        _detector = ObservedObject(wrappedValue: FullscreenMediaDetector())
        
        nowPlaying = NowPlaying()
        
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")) else {
            print("Failed to load MediaRemote.framework")
            return nil
        }
        self.mediaRemoteBundle = bundle
        
        guard let MRMediaRemoteGetNowPlayingInfoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString),
              let MRMediaRemoteRegisterForNowPlayingNotificationsPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString)
        else {
            print("Failed to get function pointers")
            return nil
        }
        
        self.MRMediaRemoteGetNowPlayingInfo = unsafeBitCast(MRMediaRemoteGetNowPlayingInfoPointer, to: (@convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void).self)
        self.MRMediaRemoteRegisterForNowPlayingNotifications = unsafeBitCast(MRMediaRemoteRegisterForNowPlayingNotificationsPointer, to: (@convention(c) (DispatchQueue) -> Void).self)
        
        setupNowPlayingObserver()
        fetchNowPlayingInfo()
        
        self.detector.$currentAppInFullScreen
            .sink { [weak self] newValue in
                self?.fetchNowPlayingInfo(bypass: true, bundle: self?.nowPlaying.appBundleIdentifier ?? nil)
            }
            .store(in: &cancellables)
        
        if(nowPlaying.playing) {
            self.fetchNowPlayingInfo()
        }
    }
    
    
    deinit {
        debounceToggle?.cancel()
        cancellables.removeAll()
    }
    
    private func setupNowPlayingObserver() {
        MRMediaRemoteRegisterForNowPlayingNotifications(DispatchQueue.main)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"))
            .sink { [weak self] _ in
                self?.fetchNowPlayingInfo(bundle: self?.nowPlaying.appBundleIdentifier ?? nil)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"))
            .sink { [weak self] _ in
                self?.updateApp()
            }
            .store(in: &cancellables)
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchNowPlayingInfo(bundle: "com.spotify.client")
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchNowPlayingInfo(bundle: "com.apple.Music")
        }
    }
    
    @objc func updateApp() {
        self.bundleIdentifier = nowPlaying.appBundleIdentifier
    }
    
    @objc func fetchNowPlayingInfo(bypass: Bool = false, bundle: String? = nil) {
        if musicToggledManually && !bypass {
            return
        }
        
        if let bundle = bundle as String? {
            bundleIdentifier = bundle
        }
        
        MRMediaRemoteGetNowPlayingInfo(DispatchQueue.main) { [weak self] information in
            guard let self = self else { return }
            
                // Check if the music has changed
            let newSongTitle = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            let newArtistName = information["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            let newAlbumName = information["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            var newArtworkData = information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
            
            let state: Int? = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Int
            
            
                //            if self.lastMusicItem?.title == newSongTitle &&
                //                self.lastMusicItem?.artist == newArtistName &&
                //                self.lastMusicItem?.album == newAlbumName && state == 1 && self.isPlaying && self.lastMusicItem?.artworkData != nil
                //            {
                //                return // No need to update if nothing has changed
                //            }
            
            self.lastMusicItem = (newSongTitle, newArtistName, newAlbumName, newArtworkData)
            
            print(bundleIdentifier)
            
            if newArtworkData == nil && state == 1 {
                newArtworkData = AppIcons().getIcon(bundleID: bundleIdentifier)?.tiffRepresentation!
            }
            
            if let state = state {
                self.musicIsPaused(state: state == 1, setIdle: true)
            } else if self.isPlaying {
                self.musicIsPaused(state: false, setIdle: true)
            }
            
            if let albumArtData = newArtworkData, let artworkImage = NSImage(data: albumArtData) {
                self.updateAlbumArt(newAlbumArt: artworkImage)
            }
            
            if !self.isPlaying {
                return
            }
            
            self.artistName = newArtistName
            self.songTitle = newSongTitle
            self.album = newAlbumName
        }
    }
    
    func musicIsPaused(state: Bool, bypass: Bool = false, setIdle: Bool = false) {
        if musicToggledManually && !bypass {
            return
        }
        
        withAnimation(.smooth) {
            self.isPlaying = state
            self.playbackManager.isPlaying = state
            
            if !state {
                self.lastUpdated = Date()
            }
            
            DispatchQueue.main.async {
                if self.vm.enableFullscreenMediaDetection {
                    self.vm.toggleMusicLiveActivity(status: !self.detector.currentAppInFullScreen)
                }
            }
            
            if self.isPlaying && vm.enableSneakPeek && !self.detector.currentAppInFullScreen {
                self.vm.toggleSneakPeak(status: true, type: SneakContentType.music)
            }
            
            if setIdle && state {
                self.isPlayerIdle = false
                debounceToggle?.cancel()
            } else if setIdle && !state {
                debounceToggle = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    if self.lastUpdated.timeIntervalSinceNow < -self.vm.waitInterval {
                        withAnimation {
                            self.isPlayerIdle = !self.isPlaying
                        }
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + self.vm.waitInterval, execute: debounceToggle!)
            }
        }
    }
    
    func togglePlayPause() {
        musicToggledManually = true
        
        let playState: Bool = playbackManager.playPause()
        
        musicIsPaused(state: playState, bypass: true, setIdle: true)
        
        if playState {
            fetchNowPlayingInfo(bypass: true)
        } else {
            lastUpdated = Date()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.musicToggledManually = false
        }
    }
    
    func updateAlbumArt(newAlbumArt: NSImage) {
        withAnimation(vm.animation) {
            self.albumArt = newAlbumArt
            if vm.coloredSpectrogram {
                calculateAverageColor()
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
