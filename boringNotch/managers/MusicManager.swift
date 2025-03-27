//
//  MusicManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//
import AppKit
import Combine
import Defaults
import SwiftUI

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
    private var isInitializing: Bool = true

    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var musicToggledManually: Bool = false
    @Published var album: String = "Self Love"
    @Published var lastUpdated: Date = .distantPast
    @Published var isPlayerIdle: Bool = true
    @Published var animations: BoringAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 0
    @ObservedObject var detector: FullscreenMediaDetector
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false

    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteGetNowPlayingInfo: @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private let MRMediaRemoteRegisterForNowPlayingNotifications: @convention(c) (DispatchQueue) -> Void
    private let MRMediaRemoteGetNowPlayingApplicationIsPlaying: @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private let MRMediaRemoteGetNowPlayingClient: @convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
    private let MRNowPlayingClientGetBundleIdentifier: @convention(c) (AnyObject?) -> String?
    private let MRNowPlayingClientGetParentAppBundleIdentifier: @convention(c) (AnyObject?) -> String?

    private var distributedObservers: [NSObjectProtocol] = []

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    private var elapsedTimeTimer: Timer?

    // MARK: - Initialization

    init?(vm: BoringViewModel) {
        self.vm = vm
        _detector = ObservedObject(wrappedValue: FullscreenMediaDetector())
        
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
              let MRMediaRemoteGetNowPlayingInfoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString),
              let MRMediaRemoteRegisterForNowPlayingNotificationsPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString),
              let MRMediaRemoteGetNowPlayingApplicationIsPlayingPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString),
              let MRMediaRemoteGetNowPlayingClientPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingClient" as CFString),
              let MRNowPlayingClientGetBundleIdentifierPointer = CFBundleGetFunctionPointerForName(bundle, "MRNowPlayingClientGetBundleIdentifier" as CFString),
              let MRNowPlayingClientGetParentAppBundleIdentifierPointer = CFBundleGetFunctionPointerForName(bundle, "MRNowPlayingClientGetParentAppBundleIdentifier" as CFString)
        else {
            print("Failed to load MediaRemote.framework or get function pointers")
            return nil
        }

        mediaRemoteBundle = bundle
        MRMediaRemoteGetNowPlayingInfo = unsafeBitCast(MRMediaRemoteGetNowPlayingInfoPointer, to: (@convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void).self)
        MRMediaRemoteRegisterForNowPlayingNotifications = unsafeBitCast(MRMediaRemoteRegisterForNowPlayingNotificationsPointer, to: (@convention(c) (DispatchQueue) -> Void).self)
        MRMediaRemoteGetNowPlayingApplicationIsPlaying = unsafeBitCast(MRMediaRemoteGetNowPlayingApplicationIsPlayingPointer, to: (@convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void).self)
        MRMediaRemoteGetNowPlayingClient = unsafeBitCast(MRMediaRemoteGetNowPlayingClientPointer, to: (@convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void).self)
        MRNowPlayingClientGetBundleIdentifier = unsafeBitCast(MRNowPlayingClientGetBundleIdentifierPointer, to: (@convention(c) (AnyObject?) -> String?).self)
        MRNowPlayingClientGetParentAppBundleIdentifier = unsafeBitCast(MRNowPlayingClientGetParentAppBundleIdentifierPointer, to: (@convention(c) (AnyObject?) -> String?).self)
        
        setupNowPlayingObserver()
        fetchNowPlayingInfo()

        setupDetectorObserver()

        isInitializing = false
    }

    deinit {
        debounceToggle?.cancel()
        cancellables.removeAll()

        for observer in distributedObservers {
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
            self?.fetchNowPlayingInfo()
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
            .sink { [weak self] isFullScreen in
                self?.vm.toggleMusicLiveActivity(status: !(isFullScreen))
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
        // Get the now playing client
        MRMediaRemoteGetNowPlayingClient(DispatchQueue.main) { [weak self] clientObj in
            guard let clientObj = clientObj else {
                DispatchQueue.main.async {
                    self?.bundleIdentifier = "com.apple.Music" // Default fallback
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
                self?.bundleIdentifier = appBundleID ?? "com.apple.Music"
            }
        }
    }

    @objc func fetchNowPlayingInfo(bypass: Bool = false, bundle: String? = nil) {
        if musicToggledManually && !bypass { return }

        if(bundle != nil) {
            bundleIdentifier = bundle
        } else {
            updateApp()
        }

        MRMediaRemoteGetNowPlayingInfo(DispatchQueue.main) { [weak self] information in
            guard let self = self else { return }

            let newInfo = self.extractMusicInfo(from: information)
            let state: Int? = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Int

            self.updateMusicState(newInfo: newInfo, state: state)

            let playbackRate = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 1
            
            guard let elapsedTime = information["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval,
                  let timestampDate = information["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date
            else {
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

    private func extractMusicInfo(from information: [String: Any]) -> (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?) {
        let title = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        let artist = information["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = information["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        let duration = information["kMRMediaRemoteNowPlayingInfoDuration"] as? TimeInterval ?? lastMusicItem?.duration ?? 0
        let artworkData = information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data

        return (title, artist, album, duration, artworkData)
    }

    private func updateMusicState(newInfo: (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?), state _: Int?) {
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
            
            updateArtwork(newInfo.artworkData)
            lastMusicItem?.artworkData = newInfo.artworkData

            // Only update sneak peek if there's actual content
            if musicInfoChanged && !newInfo.title.isEmpty && !newInfo.artist.isEmpty {
                updateSneakPeek()
            }
        }

        lastMusicItem = (
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
                if isPlaying != self?.isPlaying {
                    self?.updatePlaybackState(state: isPlaying)
                }
            }
        }
    }

    private func updateArtwork(_ artworkData: Data?) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let newArt: NSImage?
            let usingAppIcon: Bool

            if let artworkData = artworkData,
               let artworkImage = NSImage(data: artworkData)
            {
                newArt = artworkImage
                usingAppIcon = false
            } else if let appIconImage = AppIconAsNSImage(for: self.bundleIdentifier ?? "") {
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

    func updatePlaybackState(state: Bool, bypass: Bool = false) {
        // Only update lastUpdated when pausing the music and not during initialization
        if !state && !isInitializing {
            lastUpdated = Date()
        }
        
        if musicToggledManually && !bypass { return }

        withAnimation(.smooth) {
            // Batch related state updates
            self.isPlaying = state

            if !songTitle.isEmpty && !artistName.isEmpty {
                updateSneakPeek()
            }

            updateIdleState(state: state)
        }
    }

    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] && !detector.currentAppInFullScreen {
            coordinator.toggleSneakPeek(status: true, type: SneakContentType.music)
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceToggle?.cancel()
        } else {
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

    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }
}
