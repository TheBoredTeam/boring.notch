//
//  MusicManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//
import AppKit
import Combine
import SwiftUI
import Defaults

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {

    // MARK: - Properties
    private var cancellables = Set<AnyCancellable>()
    private var debounceToggle: DispatchWorkItem?
    private var vm: BoringViewModel
    private var lastMusicItem: (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?)?
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
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = Date()
    @Published var playbackRate: Double = 0
    @ObservedObject var detector: FullscreenMediaDetector
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    var nowPlaying: NowPlaying
    
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteGetNowPlayingInfo: @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private let MRMediaRemoteRegisterForNowPlayingNotifications: @convention(c) (DispatchQueue) -> Void
    private let MRMediaRemoteGetNowPlayingApplicationIsPlaying: @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    
    private var distributedObservers: [NSObjectProtocol] = []
    
    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?
    
    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?
    
    // MARK: - Initialization
    init?(vm: BoringViewModel) {
        self.vm = vm
        _detector = ObservedObject(wrappedValue: FullscreenMediaDetector())
        nowPlaying = NowPlaying()
        
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
              let MRMediaRemoteGetNowPlayingInfoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString),
              let MRMediaRemoteRegisterForNowPlayingNotificationsPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString),
              let MRMediaRemoteGetNowPlayingApplicationIsPlayingPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString)
        else {
            print("Failed to load MediaRemote.framework or get function pointers")
            return nil
        }
        
        self.mediaRemoteBundle = bundle
        self.MRMediaRemoteGetNowPlayingInfo = unsafeBitCast(MRMediaRemoteGetNowPlayingInfoPointer, to: (@convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void).self)
        self.MRMediaRemoteRegisterForNowPlayingNotifications = unsafeBitCast(MRMediaRemoteRegisterForNowPlayingNotificationsPointer, to: (@convention(c) (DispatchQueue) -> Void).self)
        self.MRMediaRemoteGetNowPlayingApplicationIsPlaying = unsafeBitCast(MRMediaRemoteGetNowPlayingApplicationIsPlayingPointer, to: (@convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void).self)
        
        
        setupNowPlayingObserver()
        fetchNowPlayingInfo()
        
        setupDetectorObserver()
        
        if nowPlaying.playing {
            self.fetchNowPlayingInfo()
        }
    }
    
    deinit {
        debounceToggle?.cancel()
        cancellables.removeAll()
        
        distributedObservers.forEach { observer in
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        distributedObservers.removeAll()
        
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()
    }
    
    // MARK: - Setup Methods
    private func setupNowPlayingObserver() {
        MRMediaRemoteRegisterForNowPlayingNotifications(DispatchQueue.main)
        
        observeNotification(name: "kMRMediaRemoteNowPlayingInfoDidChangeNotification") { [weak self] in
            self?.fetchNowPlayingInfo(bundle: self?.nowPlaying.appBundleIdentifier ?? nil)
        }
        
        observeNotification(name: "kMRMediaRemoteNowPlayingApplicationDidChangeNotification") { [weak self] in
            self?.updateApp()
        }
        
        observeDistributedNotification(name: "com.spotify.client.PlaybackStateChanged") { [weak self] in
            self?.fetchNowPlayingInfo(bundle: "com.spotify.client")
        }
        
        observeDistributedNotification(name: "com.apple.Music.playerInfo") { [weak self] in
            self?.fetchNowPlayingInfo(bundle: "com.apple.Music")
        }
    }
    
    private func setupDetectorObserver() {
        detector.$currentAppInFullScreen
            .sink { [weak self] _ in
                self?.fetchNowPlayingInfo(bypass: true, bundle: self?.nowPlaying.appBundleIdentifier ?? nil)
            }
            .store(in: &cancellables)
    }
    
    private func observeNotification(name: String, handler: @escaping () -> Void) {
        NotificationCenter.default.publisher(for: NSNotification.Name(name))
            .sink { _ in handler() }
            .store(in: &cancellables)
    }
    
    private func observeDistributedNotification(name: String, handler: @escaping () -> Void) {
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(name),
            object: nil,
            queue: .main
        ) { _ in handler() }
        distributedObservers.append(observer)
    }
    
    // MARK: - Update Methods
    @objc func updateApp() {
        self.bundleIdentifier = nowPlaying.appBundleIdentifier ?? "com.apple.Music"
    }
    
    @objc func fetchNowPlayingInfo(bypass: Bool = false, bundle: String? = nil) {
        if musicToggledManually && !bypass { return }
        
        updateBundleIdentifier(bundle)
        
        MRMediaRemoteGetNowPlayingInfo(DispatchQueue.main) { [weak self] information in
            guard let self = self else { return }
            
            let newInfo = self.extractMusicInfo(from: information)
            let state: Int? = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Int
            
            self.updateMusicState(newInfo: newInfo, state: state)
            
            guard let elapsedTime = information["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval,
                  let timestampDate = information["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date,
                  let playbackRate = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double else {
                return
            }
            
            DispatchQueue.main.async {
                self.elapsedTime = elapsedTime
                self.timestampDate = timestampDate
                self.playbackRate = playbackRate
            }
        }
    }
    
    // MARK: - Helper Methods
    private func updateBundleIdentifier(_ bundle: String?) {
        if let bundle = bundle {
            self.bundleIdentifier = bundle
            
        }
    }
    
    private func extractMusicInfo(from information: [String: Any]) -> (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?) {
        let title = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        let artist = information["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = information["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        let duration = information["kMRMediaRemoteNowPlayingInfoDuration"] as? TimeInterval ?? lastMusicItem?.duration ?? 0
        let artworkData = information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
       
        return (title, artist, album, duration, artworkData)
    }
    
    private func updateMusicState(newInfo: (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?), state: Int?) {
        // Check if music info has actually changed
        let musicInfoChanged = (newInfo.title != lastMusicItem?.title ||
                              newInfo.artist != lastMusicItem?.artist ||
                              newInfo.album != lastMusicItem?.album)
        
        let artworkChanged = newInfo.artworkData != nil && newInfo.artworkData != lastMusicItem?.artworkData
        
        if artworkChanged || musicInfoChanged {
            // Trigger flip animation
            flipWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.isFlipping = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.isFlipping = false
                }
            }
            flipWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
            
            if artworkChanged {
                updateArtwork(newInfo.artworkData)
                self.lastMusicItem?.artworkData = newInfo.artworkData
            }
            
            // Only update sneak peek if there's actual content
            if musicInfoChanged && !newInfo.title.isEmpty && !newInfo.artist.isEmpty {
                updateSneakPeek()
            }
        }
        
        self.lastMusicItem = (
            title: newInfo.title,
            artist: newInfo.artist,
            album: newInfo.album,
            duration: newInfo.duration,
            artworkData: lastMusicItem?.artworkData
        )
        
        // Batch state updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.artistName = newInfo.artist
            self.songTitle = newInfo.title
            self.album = newInfo.album
            self.songDuration = newInfo.duration
            
            // Check playback state
            MRMediaRemoteGetNowPlayingApplicationIsPlaying(DispatchQueue.main) { [weak self] isPlaying in
                self?.musicIsPaused(state: isPlaying, setIdle: true)
            }
        }
    }
    
    private func updateArtwork(_ artworkData: Data?) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let newArt: NSImage?
            let usingAppIcon: Bool
            
            if let artworkData = artworkData,
               let artworkImage = NSImage(data: artworkData) {
                newArt = artworkImage
                usingAppIcon = false
            } else if let appIconImage = AppIconAsNSImage(for: self.bundleIdentifier ?? self.nowPlaying.appBundleIdentifier ?? "") {
                newArt = appIconImage
                usingAppIcon = true
            } else {
                return
            }
            
            DispatchQueue.main.async {
                self.usingAppIconForArtwork = usingAppIcon
                self.updateAlbumArt(newAlbumArt: newArt!)
            }
        }
    }
    
    func musicIsPaused(state: Bool, bypass: Bool = false, setIdle: Bool = false) {
        if musicToggledManually && !bypass { return }
        
        let previousState = self.isPlaying
        let hasContent = !songTitle.isEmpty && !artistName.isEmpty
        
        withAnimation(.smooth) {
            // Batch related state updates
            self.isPlaying = state
            self.playbackManager.isPlaying = state
            
            if !state {
                self.lastUpdated = Date()
            }
            
            updateFullscreenMediaDetection()
            
            // Only update sneak peek if state changed and has content
            if previousState != state && hasContent {
                updateSneakPeek()
            }
            
            updateIdleState(setIdle: setIdle, state: state)
        }
    }
    
    private func updateFullscreenMediaDetection() {
        // Remove redundant dispatch since we're already on main thread
        if Defaults[.enableFullscreenMediaDetection] {
            self.vm.toggleMusicLiveActivity(status: !self.detector.currentAppInFullScreen)
        }
    }
    
    private func updateSneakPeek() {
        if self.isPlaying && Defaults[.enableSneakPeek] && !self.detector.currentAppInFullScreen {
            coordinator.toggleSneakPeek(status: true, type: SneakContentType.music)
        }
    }
    
    private func updateIdleState(setIdle: Bool, state: Bool) {
        if setIdle && state {
            self.isPlayerIdle = false
            debounceToggle?.cancel()
        } else if setIdle && !state {
            debounceToggle = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.lastUpdated.timeIntervalSinceNow < -Defaults[.waitInterval] {
                    withAnimation {
                        self.isPlayerIdle = !self.isPlaying
                    }
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + Defaults[.waitInterval], execute: debounceToggle!)
        }
    }
    
    func togglePlayPause() {
        musicToggledManually = true
        
        let playState = playbackManager.playPause()
        
        musicIsPaused(state: playState, bypass: true, setIdle: true)
        
        if playState {
            fetchNowPlayingInfo(bypass: true)
        } else {
            lastUpdated = Date()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.musicToggledManually = false
            self?.fetchNowPlayingInfo()
        }
    }
    
    private var workItem: DispatchWorkItem?
        
    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        workItem = DispatchWorkItem { [weak self] in
            withAnimation(.smooth) {
                self?.albumArt = newAlbumArt
                if Defaults[.coloredSpectrogram] {
                    self?.calculateAverageColor()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem!)
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
        playbackManager.nextTrack()
        fetchNowPlayingInfo(bypass: true)
    }
    
    func previousTrack() {
        playbackManager.previousTrack()
        fetchNowPlayingInfo(bypass: true)
    }
    
    func seekTrack(to time: TimeInterval) {
        playbackManager.seekTrack(to: time)
    }
    
    func openMusicApp() {
        guard let bundleID = nowPlaying.appBundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }
        
        let workspace = NSWorkspace.shared
        if workspace.launchApplication(withBundleIdentifier: bundleID, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil) {
            print("Launched app with bundle ID: \(bundleID)")
        } else {
            print("Failed to launch app with bundle ID: \(bundleID)")
        }
    }
}
