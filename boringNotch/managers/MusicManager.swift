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

struct NowPlayingFallbackNotice: Identifiable, Equatable {
    let id = UUID()
    let fallbackSource: MediaControllerType

    var title: LocalizedStringResource {
        LocalizedStringResource(
            "Now Playing unavailable",
            comment: "Title of the passive notice shown when the Now Playing media source cannot be used."
        )
    }

    var subtitle: LocalizedStringResource {
        LocalizedStringResource(
            "Using \(fallbackSource.localizedString) temporarily",
            comment: "Temporary Now Playing fallback notice. The placeholder is the fallback music source name."
        )
    }
}

@MainActor
final class MusicManager: ObservableObject {
    // MARK: - Properties
    static let shared = MusicManager()
    private static let noticeDuration: Duration = .seconds(6)

    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?
    private var availabilityTask: Task<Void, Never>?
    private var runtimeFailureTask: Task<Void, Never>?
    private var noticeDismissalTask: Task<Void, Never>?
    private var isDestroyed = false
    private var didShowNoticeForCurrentFailure = false

    // Helper to check if macOS can use NowPlayingController
    @Published private(set) var preferredMediaController: MediaControllerType
    @Published private(set) var nowPlayingAvailability: NowPlayingAvailability = .unchecked
    @Published private(set) var effectiveMediaController: MediaControllerType?
    @Published private(set) var nowPlayingNotice: NowPlayingFallbackNotice?

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Published properties for UI
    @Published var songTitle: String = ""
    @Published var artistName: String = ""
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = ""
    @Published var isPlayerIdle: Bool = true
    @Published var animations: BoringAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var audioCaptureBundleIdentifiers: [String] = []
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported: Bool = true
    private let coordinator = BoringViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published var canFavoriteTrack: Bool = false
    
    // Lyrics are now managed by LyricsService
    var lyricsService: LyricsService { LyricsService.shared }
    var currentLyrics: String { lyricsService.currentLyrics }
    var isFetchingLyrics: Bool { lyricsService.isFetchingLyrics }
    var syncedLyrics: [(time: Double, text: String)] { lyricsService.syncedLyrics }
    @Published var isFavoriteTrack: Bool = false

    private var artworkData: Data? = nil

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = ""
    private var lastArtworkArtist: String = ""
    private var lastArtworkAlbum: String = ""
    private var lastArtworkBundleIdentifier: String? = nil

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    // MARK: - Initialization
    init() {
        Self.migrateMediaControllerPreferenceIfNeeded()
        preferredMediaController = Defaults[.mediaController]

        if preferredMediaController == .nowPlaying {
            activateFallback(showNotice: false)
            ensureNowPlayingAvailabilityChecked()
        } else {
            activateControllerIfNeeded(preferredMediaController)
        }
    }

    private static func migrateMediaControllerPreferenceIfNeeded() {
        guard !Defaults[.didMigrateMediaControllerChoice] else { return }

        let firstLaunch = UserDefaults.standard.object(forKey: "firstLaunch") as? Bool ?? true
        let hasStoredController = UserDefaults.standard.object(forKey: "mediaController") != nil
        Defaults[.didChooseMediaController] = Defaults[.didChooseMediaController]
            || hasStoredController
            || !firstLaunch
        Defaults[.didMigrateMediaControllerChoice] = true
    }

    deinit {
        debounceIdleTask?.cancel()
        availabilityTask?.cancel()
        runtimeFailureTask?.cancel()
        noticeDismissalTask?.cancel()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()
    }

    func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true

        debounceIdleTask?.cancel()
        availabilityTask?.cancel()
        runtimeFailureTask?.cancel()
        noticeDismissalTask?.cancel()
        availabilityTask = nil
        runtimeFailureTask = nil
        noticeDismissalTask = nil
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()
        (activeController as? any NowPlayingRuntimeControlling)?.stopRuntimeStream()

        activeController = nil
        effectiveMediaController = nil
        nowPlayingNotice = nil
    }

    func selectMediaController(_ type: MediaControllerType) {
        guard !isDestroyed else { return }

        Defaults[.mediaController] = type
        Defaults[.didChooseMediaController] = true
        preferredMediaController = type
        clearNotice()

        if type == .nowPlaying {
            if nowPlayingAvailability == .available {
                activateControllerIfNeeded(.nowPlaying)
            } else {
                activateFallback(showNotice: false)
                refreshNowPlayingAvailability()
            }
        } else {
            activateControllerIfNeeded(type)
        }
    }

    private func resolvedNowPlayingFallback() -> MediaControllerType {
        guard let bundleIdentifier = Defaults[.lastSupportedNowPlayingBundleIdentifier],
              let controller = MediaControllerType(nowPlayingBundleIdentifier: bundleIdentifier)
        else {
            return .appleMusic
        }

        return controller
    }

    func ensureNowPlayingAvailabilityChecked() {
        guard nowPlayingAvailability == .unchecked else { return }
        startAvailabilityCheck()
    }

    func refreshNowPlayingAvailability() {
        startAvailabilityCheck()
    }

    private func startAvailabilityCheck() {
        guard !isDestroyed, availabilityTask == nil else { return }

        nowPlayingAvailability = .checking
        availabilityTask = Task { @MainActor [weak self] in
            let availability: NowPlayingAvailability
            do {
                availability = try await MediaChecker().checkAvailability(maxAttempts: 3)
            } catch is CancellationError {
                return
            } catch {
                availability = .unavailable
            }

            guard let self, !self.isDestroyed else { return }
            self.availabilityTask = nil
            self.nowPlayingAvailability = availability

            if availability == .available {
                self.clearNotice()
                if self.preferredMediaController == .nowPlaying {
                    self.activateControllerIfNeeded(.nowPlaying)
                }
            } else if self.preferredMediaController == .nowPlaying {
                self.activateFallback(showNotice: Defaults[.didChooseMediaController])
            }
        }
    }

    private func activateFallback(showNotice: Bool) {
        let fallbackController = resolvedNowPlayingFallback()

        if showNotice {
            requestNotice(fallbackController: fallbackController)
        }

        activateControllerIfNeeded(fallbackController)
    }

    private func requestNotice(fallbackController: MediaControllerType) {
        guard !didShowNoticeForCurrentFailure else { return }
        didShowNoticeForCurrentFailure = true

        nowPlayingNotice = NowPlayingFallbackNotice(fallbackSource: fallbackController)
    }

    @discardableResult
    func markNowPlayingNoticePresented(_ noticeID: UUID) -> Bool {
        guard nowPlayingNotice?.id == noticeID,
              noticeDismissalTask == nil
        else {
            return false
        }

        noticeDismissalTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: Self.noticeDuration)
            } catch {
                return
            }
            guard self.nowPlayingNotice?.id == noticeID else { return }
            self.nowPlayingNotice = nil
            self.noticeDismissalTask = nil
        }
        return true
    }

    private func clearNotice() {
        noticeDismissalTask?.cancel()
        noticeDismissalTask = nil
        nowPlayingNotice = nil
        didShowNoticeForCurrentFailure = false
    }

    private func activateControllerIfNeeded(_ type: MediaControllerType) {
        guard !isDestroyed,
              activeController == nil || effectiveMediaController != type
        else {
            return
        }

        do {
            let controller = try makeController(for: type)
            activateController(controller, type: type)
        } catch {
            if type == .nowPlaying {
                nowPlayingAvailability = .unavailable
                activateFallback(showNotice: Defaults[.didChooseMediaController])
                return
            }

            guard type != .appleMusic else { return }
            activateController(AppleMusicController(), type: .appleMusic)
        }
    }

    private func makeController(
        for type: MediaControllerType
    ) throws -> any MediaControllerProtocol {
        switch type {
        case .nowPlaying:
            try NowPlayingController()
        case .appleMusic:
            AppleMusicController()
        case .spotify:
            SpotifyController()
        case .youtubeMusic:
            YouTubeMusicController()
        }
    }

    private func activateController(
        _ controller: any MediaControllerProtocol,
        type: MediaControllerType
    ) {
        let isReplacingController = activeController != nil

        runtimeFailureTask?.cancel()
        runtimeFailureTask = nil
        (activeController as? any NowPlayingRuntimeControlling)?.stopRuntimeStream()
        controllerCancellables.removeAll()

        flipWorkItem?.cancel()
        if isReplacingController {
            resetPublishedPlaybackState()
        }
        activeController = controller
        effectiveMediaController = type
        canFavoriteTrack = controller.supportsFavorite
        volumeControlSupported = controller.supportsVolumeControl

        controller.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self, controller] state in
                guard let self,
                      self.activeController === controller,
                      state.lastUpdated != .distantPast
                else {
                    return
                }
                self.updateFromPlaybackState(state)
            }
            .store(in: &controllerCancellables)

        if let runtimeController = controller as? any NowPlayingRuntimeControlling {
            runtimeFailureTask = Task { @MainActor [weak self, runtimeController] in
                for await _ in runtimeController.runtimeFailures {
                    guard let self else { return }
                    self.handleRuntimeFailure(from: runtimeController)
                }
            }
        }

        forceUpdate()
        (controller as? any NowPlayingRuntimeControlling)?.startRuntimeStream()
    }

    private func resetPublishedPlaybackState() {
        debounceIdleTask?.cancel()
        debounceIdleTask = nil

        songTitle = ""
        artistName = ""
        album = ""
        albumArt = defaultImage
        isPlaying = false
        isPlayerIdle = true
        avgColor = .white
        bundleIdentifier = nil
        audioCaptureBundleIdentifiers = []
        songDuration = 0
        elapsedTime = 0
        timestampDate = Date()
        playbackRate = 1
        isShuffled = false
        repeatMode = .off
        volume = 0.5
        usingAppIconForArtwork = false
        isFavoriteTrack = false

        artworkData = nil
        lastArtworkTitle = ""
        lastArtworkArtist = ""
        lastArtworkAlbum = ""
        lastArtworkBundleIdentifier = nil
        lyricsService.clearLyrics()
    }

    private func handleRuntimeFailure(from controller: any NowPlayingRuntimeControlling) {
        guard activeController === controller,
              effectiveMediaController == .nowPlaying,
              preferredMediaController == .nowPlaying
        else {
            return
        }

        NSLog("Now Playing runtime stream failed; switching to fallback")
        nowPlayingAvailability = .unavailable
        activateFallback(showNotice: Defaults[.didChooseMediaController])
    }

    // MARK: - Update Methods
    private func updateFromPlaybackState(_ state: PlaybackState) {
        guard state.lastUpdated != .distantPast else { return }

        if effectiveMediaController == .nowPlaying,
           MediaControllerType(nowPlayingBundleIdentifier: state.bundleIdentifier) != nil,
           Defaults[.lastSupportedNowPlayingBundleIdentifier] != state.bundleIdentifier {
            Defaults[.lastSupportedNowPlayingBundleIdentifier] = state.bundleIdentifier
        }

        // Check for playback state changes (playing/paused)
        if state.isPlaying != self.isPlaying {
            NSLog("Playback state changed: \(state.isPlaying ? "Playing" : "Paused")")
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
                } else {
                    self.usingAppIconForArtwork = false
                    self.updateAlbumArt(newAlbumArt: defaultImage)
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

            // Fetch lyrics on content change
            self.fetchLyricsIfAvailable(bundleIdentifier: state.bundleIdentifier, title: state.title, artist: state.artist)
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = state.volume != self.volume
        
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
            // Update volume control support from active controller
            self.volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        let captureBundleIDs = state.effectiveAudioCaptureBundleIdentifiers
        if captureBundleIDs != self.audioCaptureBundleIdentifiers {
            self.audioCaptureBundleIdentifiers = captureBundleIDs
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        if state.isFavorite != self.isFavoriteTrack {
            self.isFavoriteTrack = state.isFavorite
        }
        
        if volumeChanged {
            self.volume = state.volume
        }
        
        self.timestampDate = state.lastUpdated
    }

    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
        // Toggle based on current state
        setFavorite(!isFavoriteTrack)
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        Task { @MainActor in
            await controller.setFavorite(favorite)
            try? await Task.sleep(for: .milliseconds(150))
            await controller.updatePlaybackInfo()
        }
    }

    /// Placeholder dislike function
    func dislikeCurrentTrack() {
        setFavorite(false)
    }

    // MARK: - Lyrics
    private func fetchLyricsIfAvailable(bundleIdentifier: String?, title: String, artist: String) {
        guard Defaults[.enableLyrics], !title.isEmpty else {
            Task { @MainActor in
                lyricsService.clearLyrics()
            }
            return
        }
        
        Task { @MainActor in
            await lyricsService.fetchLyrics(bundleIdentifier: bundleIdentifier, title: title, artist: artist)
        }
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
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        withAnimation(.smooth) {
            self.albumArt = newAlbumArt
            if Defaults[.coloredSpectrogram] {
                self.calculateAverageColor()
            }
        }
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
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
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func nextTrack() {
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }
    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, elapsedTime + seconds), songDuration)
        seek(to: newPos)
    }
    
    func setVolume(to level: Double) {
        if let controller = activeController {
            Task {
                await controller.setVolume(level)
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

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                if let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }
    
    
    func syncVolumeFromActiveApp() async {
        // Check if bundle identifier is valid and if the app is actually running
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { return }
        
        var script: String?
        if bundleID == "com.apple.Music" {
            script = """
            tell application "Music"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else if bundleID == "com.spotify.client" {
            script = """
            tell application "Spotify"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else {
            // For unsupported apps, don't sync volume
            return
        }
        
        if let volumeScript = script,
           let result = try? await AppleScriptHelper.execute(volumeScript) {
            let volumeValue = result.int32Value
            let currentVolume = Double(volumeValue) / 100.0
            
            await MainActor.run {
                if abs(currentVolume - self.volume) > 0.01 {
                    self.volume = currentVolume
                }
            }
        }
    }
}
