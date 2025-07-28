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
import OSLog

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {
    // MARK: - Properties
    static let shared = MusicManager()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "boringNotch", category: "MusicManager")
    
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceToggle: DispatchWorkItem?
    
    // Error handling
    @Published var lastError: AppError?

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
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

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    // MARK: - Initialization
    init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                Self.logger.info("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                Self.logger.error("Failed to check deprecation status: \(error.localizedDescription)")
                self.isNowPlayingDeprecated = false
                self.lastError = AppError.unknown(error)
            }
            
            // Initialize the active controller after deprecation check
            self.setActiveControllerBasedOnPreference()
        }
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceToggle?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()

        // Release active controller
        activeController = nil
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) throws -> (any MediaControllerProtocol)? {
        // Cleanup previous controller
        if activeController != nil {
            controllerCancellables.removeAll()
            activeController = nil
        }

        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                Self.logger.warning("NowPlaying controller is deprecated on this macOS version")
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        }

        // Set up state observation for the new controller
        if let controller = newController {
            controller.playbackStatePublisher
                .sink { [weak self] state in
                    guard let self = self,
                          self.activeController === controller else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
            
            Self.logger.info("Created \(type.displayName) controller successfully")
        } else {
            Self.logger.error("Failed to create controller for \(type.displayName)")
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]
        Self.logger.info("Setting media controller to: \(preferredType.displayName)")

        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType = (self.isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType
        
        do {
            if let controller = try createController(for: controllerType) {
                setActiveController(controller)
                lastError = nil
            } else if controllerType != .appleMusic {
                // Fallback to Apple Music if preferred controller couldn't be created
                Self.logger.warning("Falling back to Apple Music controller")
                if let fallbackController = try createController(for: .appleMusic) {
                    setActiveController(fallbackController)
                    lastError = nil
                } else {
                    throw AppError.musicServiceUnavailable
                }
            } else {
                throw AppError.mediaControllerNotFound(controllerType)
            }
        } catch {
            Self.logger.error("Failed to create controller: \(error.localizedDescription)")
            lastError = error as? AppError ?? AppError.unknown(error)
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Cancel any existing flip animation
        flipWorkItem?.cancel()

        // Set new active controller
        activeController = controller

        // Get current state from active controller
        forceUpdate()
    }

    // MARK: - Update Methods
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Create a batch of updates to apply together
        let updateBatch = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Check for playback state changes (playing/paused)
            if state.isPlaying != self.isPlaying {
                withAnimation(.smooth) {
                    self.isPlaying = state.isPlaying
                    self.updateIdleState(state: state.isPlaying)
                }

                if state.isPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                    self.updateSneakPeek()
                }
            }

            // Check for changes in track metadata using last artwork change values
            let titleChanged = state.title != self.lastArtworkTitle
            let artistChanged = state.artist != self.lastArtworkArtist
            let albumChanged = state.album != self.lastArtworkAlbum
            let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier

            // Check for artwork changes
            let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
            let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged

            // Handle artwork and visual transitions for changed content
            if hasContentChange {
                self.triggerFlipAnimation()

                if artworkChanged, let artwork = state.artwork {
                    self.updateArtwork(artwork)
                } else if state.artwork == nil {
                    // Try to use app icon if no artwork but track changed
                    if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                        self.usingAppIconForArtwork = true
                        self.updateAlbumArt(newAlbumArt: appIconImage)
                    }
                }
                self.artworkData = state.artwork

                if artworkChanged || state.artwork == nil {
                    // Update last artwork change values
                    self.lastArtworkTitle = state.title
                    self.lastArtworkArtist = state.artist
                    self.lastArtworkAlbum = state.album
                    self.lastArtworkBundleIdentifier = state.bundleIdentifier
                }

                // Only update sneak peek if there's actual content and something changed
                if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                    self.updateSneakPeek()
                }
            }

            let timeChanged = state.currentTime != self.elapsedTime
            let durationChanged = state.duration != self.songDuration
            let playbackRateChanged = state.playbackRate != self.playbackRate
            let shuffleChanged = state.isShuffled != self.isShuffled
            let repeatModeChanged = state.repeatMode != self.repeatMode

            if state.title != self.songTitle {
                self.songTitle = state.title
            }

            if state.artist != self.artistName {
                self.artistName = state.artist
            }

            if state.album != self.album {
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
                self.isShuffled = state.isShuffled
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
                if self.timestampDate.timeIntervalSinceNow < -Defaults[.waitInterval] {
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
        guard let controller = activeController else {
            Self.logger.error("No active controller available for playPause")
            lastError = AppError.musicServiceUnavailable
            return
        }
        controller.togglePlay()
    }

    func play() {
        guard let controller = activeController else {
            Self.logger.error("No active controller available for play")
            lastError = AppError.musicServiceUnavailable
            return
        }
        controller.play()
    }

    func pause() {
        guard let controller = activeController else {
            Self.logger.error("No active controller available for pause")
            lastError = AppError.musicServiceUnavailable
            return
        }
        controller.pause()
    }

    func toggleShuffle() {
        guard let controller = activeController else {
            Self.logger.error("No active controller available for toggleShuffle")
            lastError = AppError.musicServiceUnavailable
            return
        }
        controller.toggleShuffle()
    }

    func toggleRepeat() {
        guard let controller = activeController else {
            Self.logger.error("No active controller available for toggleRepeat")
            lastError = AppError.musicServiceUnavailable
            return
        }
        controller.toggleRepeat()
    }
    
    func togglePlay() {
        guard let controller = activeController else {
            Self.logger.error("No active controller available for togglePlay")
            lastError = AppError.musicServiceUnavailable
            return
        }
        controller.togglePlay()
    }

    func nextTrack() {
        guard let controller = activeController else {
            Self.logger.error("No active controller available for nextTrack")
            lastError = AppError.musicServiceUnavailable
            return
        }
        controller.nextTrack()
    }

    func previousTrack() {
        guard let controller = activeController else {
            Self.logger.error("No active controller available for previousTrack")
            lastError = AppError.musicServiceUnavailable
            return
        }
        controller.previousTrack()
    }

    func seek(to position: TimeInterval) {
        guard let controller = activeController else {
            Self.logger.error("No active controller available for seek")
            lastError = AppError.musicServiceUnavailable
            return
        }
        controller.seek(to: position)
    }

    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            Self.logger.error("Cannot open music app: bundle identifier is nil")
            lastError = AppError.invalidState("No music app bundle identifier available")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { [weak self] (app, error) in
                if let error = error {
                    Self.logger.error("Failed to launch app with bundle ID '\(bundleID)': \(error.localizedDescription)")
                    self?.lastError = AppError.systemServiceUnavailable("Failed to launch \(bundleID)")
                } else {
                    Self.logger.info("Successfully launched app with bundle ID: \(bundleID)")
                    self?.lastError = nil
                }
            }
        } else {
            Self.logger.error("Failed to find app with bundle ID: \(bundleID)")
            lastError = AppError.fileNotFound("Application with bundle ID '\(bundleID)' not found")
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard let controller = self.activeController else {
                Self.logger.warning("No active controller to force update")
                self.lastError = AppError.musicServiceUnavailable
                return
            }
            
            if controller.isActive() {
                if self.bundleIdentifier == "com.github.th-ch.youtube-music",
                   let youtubeController = controller as? YouTubeMusicController {
                    youtubeController.pollPlaybackState()
                } else {
                    controller.updatePlaybackInfo()
                }
                Self.logger.debug("Forced update on active controller")
            } else {
                Self.logger.warning("Controller is not active, cannot force update")
                self.lastError = AppError.invalidState("Music controller is not active")
            }
        }
    }
    
    // MARK: - Error Management
    func clearError() {
        lastError = nil
    }
}
