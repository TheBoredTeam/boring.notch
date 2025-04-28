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
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceToggle: DispatchWorkItem?
    
    // Helper to check if macOS is too new for NowPlayingController
    public var isNowPlayingDeprecated: Bool {
        if #available(macOS 15.4, *) {
            return true
        }
        return false
    }

    // Controllers for all running music apps
    private var controllers: [any MediaControllerProtocol] = []
    private var activeControllerIndex: Int = 0
    @Published var availableControllerTypes: [MediaControllerType] = []

    // Active controller
    private var activeController: (any MediaControllerProtocol)? {
        guard !controllers.isEmpty, activeControllerIndex < controllers.count else { return nil }
        return controllers[activeControllerIndex]
    }

    // Current controller index for carousel UI
    @Published var currentControllerIndex: Int = 0
    @Published var totalControllerCount: Int = 0
    
    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var lastUpdated: Date = .distantPast
    @Published var ignoreLastUpdated = true
    @Published var isPlayerIdle: Bool = true
    @Published var animations: BoringAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    
    private var artworkData: Data? = nil

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    // MARK: - Initialization
    init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.initializeControllers()
            }
            .store(in: &cancellables)
        
        // Listen for app launches
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] notification in
                if let launchedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   let bundleID = launchedApp.bundleIdentifier,
                   self?.isMusicApp(bundleID: bundleID) == true {
                    // Delay slightly to ensure app is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.initializeControllers()
                    }
                }
            }
            .store(in: &cancellables)
        
        // Listen for app terminations
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] notification in
                if let terminatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   let bundleID = terminatedApp.bundleIdentifier,
                   self?.isMusicApp(bundleID: bundleID) == true {
                    // Delay slightly for cleanup
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.initializeControllers()
                    }
                }
            }
            .store(in: &cancellables)
        
        // Initialize the controllers
        initializeControllers()
    }

    deinit {
        debounceToggle?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()
        
        // Release active controller
        controllers.removeAll()
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        
        let newController: (any MediaControllerProtocol)?
        print("Creating controller for type: \(type)")
        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if (!self.isNowPlayingDeprecated) {
                ignoreLastUpdated = false
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            print("Creating Apple Music controller")
            ignoreLastUpdated = true
            newController = AppleMusicController()
        case .spotify:
            print("Creating Spotify controller")
            ignoreLastUpdated = true
            newController = SpotifyController()
        case .youtubeMusic:
            print("Creating YouTube Music controller")
            ignoreLastUpdated = true
            newController = YouTubeMusicController()
        }
        return newController
    }

    // MARK: - Update Methods
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Create a batch of updates to apply together
        let updateBatch = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Check for playback state changes (playing/paused)
            if state.isPlaying != self.isPlaying {
                self.lastUpdated = Date()
                withAnimation(.smooth) {
                    self.isPlaying = state.isPlaying
                    self.updateIdleState(state: state.isPlaying)
                }
                
                if state.isPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                    self.updateSneakPeek()
                }
            }
            
            // Check for changes in track metadata
            let titleChanged = state.title != self.songTitle
            let artistChanged = state.artist != self.artistName
            let albumChanged = state.album != self.album
            
            // Check for artwork changes
            let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
            let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged
            
            // Handle artwork and visual transitions for changed content
            if hasContentChange {
                self.triggerFlipAnimation()
                
                if artworkChanged, let artwork = state.artwork {
                    self.updateArtwork(artwork)
                } else if hasContentChange && state.artwork == nil {
                    // Try to use app icon if no artwork but track changed
                    if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                        self.usingAppIconForArtwork = true
                        self.updateAlbumArt(newAlbumArt: appIconImage)
                    }
                }
                self.artworkData = state.artwork
                
                // Only update sneak peek if there's actual content and something changed
                if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                    self.updateSneakPeek()
                }
            }
            
            let timeChanged = state.currentTime != self.elapsedTime
            let durationChanged = state.duration != self.songDuration
            let playbackRateChanged = state.playbackRate != self.playbackRate
            let shuffleChanged = (state.isShuffled ?? false) != self.isShuffled
            let repeatModeChanged = state.repeatMode != self.repeatMode

            if titleChanged {
                self.songTitle = state.title
            }
            
            if artistChanged {
                self.artistName = state.artist
            }
            
            if albumChanged {
                self.album = state.album
            }
            
            if timeChanged {
                self.elapsedTime = state.currentTime
            }
            
            if durationChanged {
                self.songDuration = state.duration
            }
            
            if playbackRateChanged {
                self.playbackRate = state.playbackRate
            }

            if shuffleChanged {
                self.isShuffled = state.isShuffled ?? false
            }
            
            if state.bundleIdentifier != self.bundleIdentifier {
                self.bundleIdentifier = state.bundleIdentifier
            }

            if repeatModeChanged {
                self.repeatMode = state.repeatMode
            }
            
            self.timestampDate = state.lastUpdated
        }
        
        // Execute the batch update on the main thread
        DispatchQueue.main.async(execute: updateBatch)
    }
    
    private func triggerFlipAnimation() {
        // Cancel any existing animation
        flipWorkItem?.cancel()
        
        // Create a new animation
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }
        
        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async {
                    self.usingAppIconForArtwork = false
                    self.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
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

            DispatchQueue.main.asyncAfter(
                deadline: .now() + Defaults[.waitInterval], execute: debounceToggle!)
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
    
    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        activeController?.togglePlay()
    }
    
    func play() {
        activeController?.play()
    }
    
    func pause() {
        activeController?.pause()
    }

    func toggleShuffle() {
        activeController?.toggleShuffle()
        refreshController()
    }

    func toggleRepeat() {
        activeController?.toggleRepeat()
        refreshController()
    }
    
    func togglePlay() {
        activeController?.togglePlay()
    }
    
    func nextTrack() {
        activeController?.nextTrack()
    }
    
    func previousTrack() {
        activeController?.previousTrack()
        refreshController()
    }
    
    func seek(to position: TimeInterval) {
        activeController?.seek(to: position)
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
    
    func forceUpdate() {
        // Request immediate update from the active controller
        DispatchQueue.main.async { [weak self] in
            if self?.activeController?.isActive() == true {
                self?.activeController?.updatePlaybackInfo()
            }
        }
    }

    func refreshController() {
        // For Spotify, force an update for correct state
        if bundleIdentifier == "com.spotify.client" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.activeController?.updatePlaybackInfo()
            }
        }
    }

    private func isMusicApp(bundleID: String) -> Bool {
        let musicAppTypes: [String: MediaControllerType] = [
            "com.spotify.client": .spotify,
            "com.github.th-ch.youtube-music": .youtubeMusic,
            "com.apple.Music": .appleMusic
        ]
        return musicAppTypes[bundleID] != nil
    }

    // Initialize all available controllers
    private func initializeControllers() {
        // Clear existing controllers and subscriptions
        controllers.removeAll()
        controllerCancellables.removeAll()
        
        let runningControllerTypes = detectRunningMusicApps()
        availableControllerTypes = runningControllerTypes
        
        for controllerType in runningControllerTypes {
            if let controller = createController(for: controllerType) {
                controllers.append(controller)
                
                // Set up state observation for this controller
                let subscription = controller.playbackStatePublisher
                    .sink { [weak self, weak controller] state in
                        guard let self = self, let controller = controller else { return }
                        
                        // If this controller starts playing and it's not active, switch to it
                        if state.isPlaying && self.activeController !== controller {
                            if let index = self.controllers.firstIndex(where: { $0 === controller }) {
                                print("🎵 Auto-switching to controller \(index) that is now playing")
                                self.switchToController(index: index)
                            }
                        }
                        
                        if controller === self.activeController {
                            self.updateFromPlaybackState(state)
                        }
                    }
                
                controllerCancellables.insert(subscription)
            }
        }
        
        totalControllerCount = controllers.count
        
        // Set the active controller index
        activeControllerIndex = min(currentControllerIndex, max(0, controllers.count - 1))
        currentControllerIndex = activeControllerIndex
        
        if let activeController = activeController {
            if let state = Mirror(reflecting: activeController).children.first(where: { $0.label == "playbackState" })?.value as? PlaybackState {
                updateFromPlaybackState(state)
            }
            
            activeController.updatePlaybackInfo()
            
            // Force update other controllers to check if any are playing
            for (index, controller) in controllers.enumerated() {
                if index != activeControllerIndex {
                    controller.updatePlaybackInfo()
                }
            }
        } else {
            isPlaying = false
            updateIdleState(state: false)
            isPlayerIdle = true
        }
    }

    private func detectRunningMusicApps() -> [MediaControllerType] {
        let runningApps = NSWorkspace.shared.runningApplications
        
        let musicAppTypes: [String: MediaControllerType] = [
            "com.spotify.client": .spotify,
            "com.github.th-ch.youtube-music": .youtubeMusic,
            "com.apple.Music": .appleMusic
        ]
        
        var runningControllerTypes: [MediaControllerType] = []
        
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  let controllerType = musicAppTypes[bundleID] else {
                continue
            }
            
            runningControllerTypes.append(controllerType)
        }
        
        if runningControllerTypes.isEmpty && !self.isNowPlayingDeprecated {
            runningControllerTypes.append(.nowPlaying)
        }
        
        return runningControllerTypes
    }

    func switchToController(index: Int) {
        print("Switching to controller at index: \(index)")
        guard index >= 0, index < controllers.count else { return }
        
        // Animation for transition
        transitionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.isTransitioning = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.isTransitioning = false
            }
        }
        transitionWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
        
        // Switch controller without clearing subscriptions
        activeControllerIndex = index
        currentControllerIndex = index
        
        if let controller = activeController {
            if let state = Mirror(reflecting: controller).children.first(where: { $0.label == "playbackState" })?.value as? PlaybackState {
                updateFromPlaybackState(state)
            }
            
            controller.updatePlaybackInfo()
        }
    }
}
