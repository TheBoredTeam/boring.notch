    //
    //  MusicManager.swift
    //  boringNotch
    //
    //  Created by Harsh Vardhan  Goswami  on 03/08/24.
    //

import SwiftUI
import Combine
import AppKit

var defaultImage:NSImage = NSImage(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    private var vm: BoringViewModel
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false {
        didSet {
            print("Will set isPlayerIdle")
            DispatchQueue.main.asyncAfter(deadline: .now() + self.vm.waitInterval) {
                self.isPlayerIdle = !self.isPlaying
            }
        }
    }
    @Published var musicToggledManually: Bool = false
    @Published var album: String = "Self Love"
    @Published var playbackManager = PlaybackManager()
    @Published var lastUpdated: Date = Date()
    @Published var isPlayerIdle: Bool = false
    @Published var animations: BoringAnimations = BoringAnimations()
    @Published var avgColor: NSColor = .white
    
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
        
        if(self.musicToggledManually) {
            return
        }
        
            // Load framework
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")) else { return }
        
            // Get a Swift function for MRMediaRemoteGetNowPlayingInfo
        guard let MRMediaRemoteGetNowPlayingInfoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) else { return }
        typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
        let MRMediaRemoteGetNowPlayingInfo = unsafeBitCast(MRMediaRemoteGetNowPlayingInfoPointer, to: MRMediaRemoteGetNowPlayingInfoFunction.self)
        
        typealias MRNowPlayingClientGetBundleIdentifierFunction = @convention(c) (AnyObject?) -> String
        
            // Get song info
        MRMediaRemoteGetNowPlayingInfo(DispatchQueue.main) { [weak self] information in
            guard let self = self else { self?.isPlaying = false; return }
            
                // Check if the song is paused
            if let state = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Int {
                
                    // Don't update lastUpdated if the song is paused and the state is the same as the previous one
                if !self.isPlaying && state == 0 {
                    self.isPlayerIdle = true
                    return
                }
                musicIsPaused(state: state == 1)
            } else {musicIsPaused(state: false)}
            
                // check if the song is same as the previous one
            if let title = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
               title == self.songTitle {
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
            
            if let artworkData = information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
               let artworkImage = NSImage(data: artworkData) {
                updateAlbumArt(newAlbumArt: artworkImage)
            } else {
                updateAlbumArt(newAlbumArt: defaultImage)
            }
            
                // Get bundle identifier
            let _MRNowPlayingClientProtobuf: AnyClass? = NSClassFromString("MRClient")
            let handle: UnsafeMutableRawPointer! = dlopen("/usr/lib/libobjc.A.dylib", RTLD_NOW)
            let allocSelector = NSSelectorFromString("alloc")
            let initSelector = NSSelectorFromString("init")
            let object = unsafeBitCast(dlsym(handle, "objc_msgSend"), to: (@convention(c) (AnyClass?, Selector?) -> AnyObject).self)(_MRNowPlayingClientProtobuf, allocSelector)
            unsafeBitCast(dlsym(handle, "objc_msgSend"), to: (@convention(c) (AnyObject?, Selector?, Any?) -> Void).self)(object, initSelector, information["kMRMediaRemoteNowPlayingInfoClientPropertiesData"] as AnyObject?)
            dlclose(handle)
        }
    }
    
    func musicIsPaused(state: Bool) {
        if(self.musicToggledManually) {
            return
        }
        self.isPlaying = state
        self.playbackManager.isPlaying = state
    }
    
    func togglePlayPause() {
        musicToggledManually = true
        
        let playState: Bool = playbackManager.playPause()
        self.isPlaying = playState
        self.playbackManager.isPlaying = playState
        
        if playState {
            fetchNowPlayingInfo(bypass: true)
        } else {
            lastUpdated = Date()
        }
        
            // Reset the manual toggle flag after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.musicToggledManually = false
        }
    }
    
    func updateAlbumArt(newAlbumArt: NSImage) {
        withAnimation(vm.animation) {
            self.albumArt = newAlbumArt
            if(vm.coloredSpectrogram) {
                calculateAverageColor()
            }
        }
    }
    
    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                self?.avgColor = color!
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
    
    deinit {
        cancellables.forEach { $0.cancel() }
    }
}
