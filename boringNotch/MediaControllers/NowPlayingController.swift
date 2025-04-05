//
//  NowPlayingController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Combine
import AppKit
import Foundation

class NowPlayingController: ObservableObject, MediaControllerProtocol {
    // MARK: - Properties
    @Published var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.apple.Music"
    )
    
    var playbackStatePublisher: Published<PlaybackState>.Publisher { $playbackState }
    private var cancellables = Set<AnyCancellable>()
    private var lastMusicItem: (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?)?
    
    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteGetNowPlayingInfo: @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private let MRMediaRemoteRegisterForNowPlayingNotifications: @convention(c) (DispatchQueue) -> Void
    private let MRMediaRemoteGetNowPlayingApplicationIsPlaying: @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private let MRMediaRemoteGetNowPlayingClient: @convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
    private let MRNowPlayingClientGetBundleIdentifier: @convention(c) (AnyObject?) -> String?
    private let MRNowPlayingClientGetParentAppBundleIdentifier: @convention(c) (AnyObject?) -> String?
    private let MRMediaRemoteSendCommandFunction:@convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void

    // MARK: - Initialization
    init?() {
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
              let MRMediaRemoteGetNowPlayingInfoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString),
              let MRMediaRemoteRegisterForNowPlayingNotificationsPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString),
              let MRMediaRemoteGetNowPlayingApplicationIsPlayingPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString),
              let MRMediaRemoteGetNowPlayingClientPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingClient" as CFString),
              let MRNowPlayingClientGetBundleIdentifierPointer = CFBundleGetFunctionPointerForName(bundle, "MRNowPlayingClientGetBundleIdentifier" as CFString),
              let MRNowPlayingClientGetParentAppBundleIdentifierPointer = CFBundleGetFunctionPointerForName(bundle, "MRNowPlayingClientGetParentAppBundleIdentifier" as CFString),
              let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString),
              let MRMediaRemoteSetElapsedTimePointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSetElapsedTime" as CFString)
        else { return nil }

        mediaRemoteBundle = bundle
        MRMediaRemoteGetNowPlayingInfo = unsafeBitCast(MRMediaRemoteGetNowPlayingInfoPointer, to: (@convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void).self)
        MRMediaRemoteRegisterForNowPlayingNotifications = unsafeBitCast(MRMediaRemoteRegisterForNowPlayingNotificationsPointer, to: (@convention(c) (DispatchQueue) -> Void).self)
        MRMediaRemoteGetNowPlayingApplicationIsPlaying = unsafeBitCast(MRMediaRemoteGetNowPlayingApplicationIsPlayingPointer, to: (@convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void).self)
        MRMediaRemoteGetNowPlayingClient = unsafeBitCast(MRMediaRemoteGetNowPlayingClientPointer, to: (@convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void).self)
        MRNowPlayingClientGetBundleIdentifier = unsafeBitCast(MRNowPlayingClientGetBundleIdentifierPointer, to: (@convention(c) (AnyObject?) -> String?).self)
        MRNowPlayingClientGetParentAppBundleIdentifier = unsafeBitCast(MRNowPlayingClientGetParentAppBundleIdentifierPointer, to: (@convention(c) (AnyObject?) -> String?).self)
        MRMediaRemoteSendCommandFunction = unsafeBitCast(MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        
        setupNowPlayingObserver()
        updatePlaybackInfo()
    }
    
    deinit {
        // Clean up all Combine subscribers
        cancellables.removeAll()
        
        // Remove distributed notification observers
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
        
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )
    }
    
    // MARK: - Protocol Implementation
    func play() {
        MRMediaRemoteSendCommandFunction(0, nil)
    }
    
    func pause() {
        MRMediaRemoteSendCommandFunction(1, nil)
    }
    
    func togglePlay() {
        MRMediaRemoteSendCommandFunction(2, nil)
    }
    
    func nextTrack() {
        MRMediaRemoteSendCommandFunction(4, nil)
    }
    
    func previousTrack() {
        MRMediaRemoteSendCommandFunction(5, nil)
    }
    
    func seek(to time: Double) {
        MRMediaRemoteSetElapsedTimeFunction(time)
    }
    
    func isActive() -> Bool {
        return true
    }
    
    // MARK: - Setup Methods
    private func setupNowPlayingObserver() {
        MRMediaRemoteRegisterForNowPlayingNotifications(DispatchQueue.main)

        NotificationCenter.default.publisher(for: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"))
            .sink { [weak self] _ in self?.updatePlaybackInfo() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"))
            .sink { [weak self] _ in self?.updateApp() }
            .store(in: &cancellables)

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(updatePlaybackInfo),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(updatePlaybackInfo),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )
    }
    
    // MARK: - Update Methods
    @objc func updateApp() {
        // Get the now playing client
        MRMediaRemoteGetNowPlayingClient(DispatchQueue.main) { [weak self] clientObj in
            guard let clientObj = clientObj else {
                DispatchQueue.main.async {
                    self?.playbackState.bundleIdentifier = "com.apple.Music" // Default fallback
                }
                return
            }
            
            // Try to get parent bundle ID first, then fall back to direct bundle ID
            var appBundleID = self?.MRNowPlayingClientGetParentAppBundleIdentifier(clientObj)
            if appBundleID == nil {
                appBundleID = self?.MRNowPlayingClientGetBundleIdentifier(clientObj)
            }
            
            // Special case for WebKit.GPU which is often Safari
            if appBundleID == "com.apple.WebKit.GPU" {
                appBundleID = "com.apple.Safari"
            }
            
            DispatchQueue.main.async {
                self?.playbackState.bundleIdentifier = appBundleID ?? "com.apple.Music"
            }
        }
    }

    @objc func updatePlaybackInfo() {
        updateApp()

        MRMediaRemoteGetNowPlayingInfo(DispatchQueue.main) { [weak self] information in
            guard let self = self else { return }

            let title = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            let artist = information["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            let album = information["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            let duration = information["kMRMediaRemoteNowPlayingInfoDuration"] as? TimeInterval ?? 0
            let currentTime = information["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval ?? 0
            let artworkData = information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
            let timestamp = information["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date ?? Date()
            let playbackRate = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 1
            
            // Update playback state
            DispatchQueue.main.async {
                                self.playbackState.title = title
                self.playbackState.artist = artist
                self.playbackState.album = album
                self.playbackState.duration = duration
                self.playbackState.currentTime = currentTime
                self.playbackState.artwork = artworkData
                self.playbackState.lastUpdated = timestamp
                self.playbackState.playbackRate = playbackRate
                
                // Check playback state
                self.MRMediaRemoteGetNowPlayingApplicationIsPlaying(DispatchQueue.main) { [weak self] isPlaying in
                    DispatchQueue.main.async {
                        self?.playbackState.isPlaying = isPlaying
                    }
                }
            }
        }
    }
}
