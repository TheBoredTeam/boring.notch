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
    private var updateQueue = DispatchQueue(label: "com.boringNotch.MusicManager.updateQueue", qos: .userInitiated)
    
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
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
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
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            if let appBundleID = self.nowPlaying.appBundleIdentifier {
                DispatchQueue.main.async {
                    self.bundleIdentifier = appBundleID
                }
            } else {
                print("Error: appBundleIdentifier is nil")
                DispatchQueue.main.async {
                    self.bundleIdentifier = "com.apple.Music"
                }
            }
        }
    }
    
    @objc func fetchNowPlayingInfo(bypass: Bool = false, bundle: String? = nil) {
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.musicToggledManually && !bypass {
                return
            }
            
            if let bundle = bundle as String? {
                DispatchQueue.main.async {
                    self.bundleIdentifier = bundle == "com.apple.WebKit.GPU" ? "com.apple.Safari" : bundle
                }
            }
            
            self.MRMediaRemoteGetNowPlayingInfo(DispatchQueue.main) { [weak self] information in
                guard let self = self else { return }
                
                let newSongTitle = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                let newArtistName = information["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                let newAlbumName = information["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
                var newArtworkData = information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
                
                let state: Int? = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Int
                
                let isNewTrack = self.lastMusicItem?.title != newSongTitle ||
                                 self.lastMusicItem?.artist != newArtistName ||
                                 self.lastMusicItem?.album != newAlbumName
                
                self.lastMusicItem = (newSongTitle, newArtistName, newAlbumName, newArtworkData)
                
                print("Media source:", self.bundleIdentifier)
                
                if newArtworkData == nil && state == 1 {
                    newArtworkData = AppIcons().getIcon(bundleID: self.bundleIdentifier)?.tiffRepresentation!
                }
                
                if let newArtworkData = newArtworkData, let artworkImage = NSImage(data: newArtworkData) {
                    self.updateAlbumArt(newAlbumArt: artworkImage)
                }
                
                if let state = state {
                    self.musicIsPaused(state: state == 1, setIdle: true)
                } else {
                    // If state is nil, check if there's any content
                    let hasContent = !newSongTitle.isEmpty || !newArtistName.isEmpty || !newAlbumName.isEmpty
                    self.musicIsPaused(state: hasContent, setIdle: true)
                }
                
                if self.isPlaying || isNewTrack {
                    DispatchQueue.main.async {
                        self.artistName = newArtistName
                        self.songTitle = newSongTitle
                        self.album = newAlbumName
                    }
                }
            }
        }
    }
    
    func musicIsPaused(state: Bool, bypass: Bool = false, setIdle: Bool = false) {
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.musicToggledManually && !bypass {
                return
            }
            
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self.isPlaying = state
                    self.playbackManager.isPlaying = state
                    
                    if !state {
                        self.lastUpdated = Date()
                    }
                    
                    if self.vm.enableFullscreenMediaDetection {
                        self.vm.toggleMusicLiveActivity(status: !self.detector.currentAppInFullScreen)
                    }
                    
                    if self.isPlaying && self.vm.enableSneakPeek && !self.detector.currentAppInFullScreen {
                        self.vm.toggleSneakPeak(status: true, type: SneakContentType.music)
                    }
                    
                    if setIdle {
                        if state {
                            self.isPlayerIdle = false
                            self.debounceToggle?.cancel()
                        } else {
                            self.debounceToggle = DispatchWorkItem { [weak self] in
                                guard let self = self else { return }
                                if self.lastUpdated.timeIntervalSinceNow < -self.vm.waitInterval {
                                    withAnimation {
                                        self.isPlayerIdle = !self.isPlaying
                                    }
                                }
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + self.vm.waitInterval, execute: self.debounceToggle!)
                        }
                    }
                }
            }
        }
    }
    
    func togglePlayPause() {
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.musicToggledManually = true
            }
            
            let playState: Bool = self.playbackManager.playPause()
            
            self.musicIsPaused(state: playState, bypass: true, setIdle: true)
            
            DispatchQueue.main.async {
                if playState {
                    self.fetchNowPlayingInfo(bypass: true)
                } else {
                    self.lastUpdated = Date()
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.musicToggledManually = false
            }
        }
    }
    
    func updateAlbumArt(newAlbumArt: NSImage) {
        DispatchQueue.main.async {
            withAnimation(.smooth) {
                self.albumArt = newAlbumArt
                if self.vm.coloredSpectrogram {
                    self.calculateAverageColor()
                }
            }
        }
    }
    
    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }
    
    func nextTrack() {
        updateQueue.async { [weak self] in
            self?.playbackManager.nextTrack()
            self?.fetchNowPlayingInfo(bypass: true)
        }
    }
    
    func previousTrack() {
        updateQueue.async { [weak self] in
            self?.playbackManager.previousTrack()
            self?.fetchNowPlayingInfo(bypass: true)
        }
    }
    
    func openMusicApp() {
        updateQueue.async { [weak self] in
            guard let self = self, let bundleID = self.nowPlaying.appBundleIdentifier else {
                print("Error: appBundleIdentifier is nil")
                return
            }

            let workspace = NSWorkspace.shared
            if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID),
               let _ = try? workspace.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) {
                print("Launched app with bundle ID: \(bundleID)")
            } else {
                print("Failed to launch app with bundle ID: \(bundleID)")
            }
        }
    }
}
