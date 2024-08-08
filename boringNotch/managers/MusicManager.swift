//
//  MusicManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//


import SwiftUI
import Combine
import AppKit

class MusicManager: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    
    @Published var songTitle: String = "I;m Handome"
    @Published var artistName: String = "Me"
    // use default image url for now
    // i'm getting Value of optional type 'NSImage?' must be unwrapped to a value of type 'NSImage'
    @Published var albumArt: NSImage = NSImage(
        systemSymbolName: "music.note",
        accessibilityDescription: "Album Art"
    )!
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var playbackManager = PlaybackManager()
    @Published var lastUpdated: Date = Date()
    
    init() {
        setupNowPlayingObserver()
        fetchNowPlayingInfo()
    }
    
    
    private func setupNowPlayingObserver() {
        // every 3 seconds, fetch now playing info
        Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchNowPlayingInfo()
            }
            .store(in: &cancellables)
    }
    
    @objc func fetchNowPlayingInfo() {
        print("Called fetchNowPlayingInfo")
        // Load framework
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")) else { return }
        
        // Get a Swift function for MRMediaRemoteGetNowPlayingInfo
        guard let MRMediaRemoteGetNowPlayingInfoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) else { return }
        typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
        let MRMediaRemoteGetNowPlayingInfo = unsafeBitCast(MRMediaRemoteGetNowPlayingInfoPointer, to: MRMediaRemoteGetNowPlayingInfoFunction.self)
        
        // Get a Swift function for MRNowPlayingClientGetBundleIdentifier
        guard let MRNowPlayingClientGetBundleIdentifierPointer = CFBundleGetFunctionPointerForName(bundle, "MRNowPlayingClientGetBundleIdentifier" as CFString) else { return }
        typealias MRNowPlayingClientGetBundleIdentifierFunction = @convention(c) (AnyObject?) -> String
        let MRNowPlayingClientGetBundleIdentifier = unsafeBitCast(MRNowPlayingClientGetBundleIdentifierPointer, to: MRNowPlayingClientGetBundleIdentifierFunction.self)
        
        // Get song info
        MRMediaRemoteGetNowPlayingInfo(DispatchQueue.main) { [weak self] information in
            guard let self = self else {
                withAnimation {
                    self?.isPlaying = false
                }
                return
            }
            
            // check if the song is paused
            if let state = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Int {
                
                
                // don't update lastUpdated if the song is paused and the state is same as the previous one
                if !self.isPlaying && state == 0 {
                    return
                }
                
                if state == 0 {
                    self.lastUpdated = Date()
                }
                
                withAnimation {
                    self.isPlaying = state == 1
                    self.playbackManager.isPlaying = state == 1
                }
                
            }
            
            // check if the song is same as the previous one
            if let title = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
               title == self.songTitle {
                return
            }
            
            if let artist = information["kMRMediaRemoteNowPlayingInfoArtist"] as? String {
                withAnimation {
                    self.artistName = artist
                }
            }
            
            if let title = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String {
                withAnimation {
                    self.songTitle = title
                }
            }
            
            if let album = information["kMRMediaRemoteNowPlayingInfoAlbum"] as? String {
                print("Album: \(album)")
                withAnimation {
                    self.album = album
                }
            }
            
            if let duration = information["kMRMediaRemoteNowPlayingInfoDuration"] as? String {
                print("Duration: \(duration)")
            }
            
            if let artworkData = information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
               let artworkImage = NSImage(data: artworkData) {
                withAnimation {
                    self.albumArt = artworkImage
                }
                print("artworkData : \(artworkData)")
            }
            
            // Get bundle identifier
            let _MRNowPlayingClientProtobuf: AnyClass? = NSClassFromString("MRClient")
            let handle: UnsafeMutableRawPointer! = dlopen("/usr/lib/libobjc.A.dylib", RTLD_NOW)
            let object = unsafeBitCast(dlsym(handle, "objc_msgSend"), to: (@convention(c) (AnyClass?, Selector?) -> AnyObject).self)(_MRNowPlayingClientProtobuf, Selector(("alloc")))
            unsafeBitCast(dlsym(handle, "objc_msgSend"), to: (@convention(c) (AnyObject?, Selector?, Any?) -> Void).self)(object, Selector(("initWithData:")), information["kMRMediaRemoteNowPlayingInfoClientPropertiesData"] as AnyObject?)
            let bundleIdentifier = MRNowPlayingClientGetBundleIdentifier(object)
            dlclose(handle)
        }
    }
    
    func togglePlayPause() {
        // Implement play/pause functionality
        playbackManager.playPause()
        
        withAnimation {
            isPlaying = playbackManager.isPlaying
        }
        
        if isPlaying {
            fetchNowPlayingInfo()
        }
        
        if !isPlaying {
            lastUpdated = Date()
        }
    }
    
    func nextTrack() {
        // Implement next track functionality
        playbackManager.nextTrack()
        fetchNowPlayingInfo()
    }
    
    func previousTrack() {
        // Implement previous track functionality
        playbackManager.previousTrack()
        fetchNowPlayingInfo()
    }
    
}
