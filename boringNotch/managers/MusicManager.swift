//
//  MusicManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//
import AppKit
import ApplicationServices
import Combine
import Defaults
import SwiftUI
import Foundation

// MARK: - Lyrics Service Models and Classes

struct LyricsLine {
    let text: String
    let startTime: Double
    let endTime: Double
}

struct LyricsResponse {
    let title: String
    let artist: String
    let lines: [LyricsLine]
    let isTimedLyrics: Bool
}

// MARK: - LRCLIB API Models

struct LRCLIBSearchResult: Codable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double?
    let plainLyrics: String?
    let syncedLyrics: String?
    
    private enum CodingKeys: String, CodingKey {
        case id
        case trackName
        case artistName
        case albumName
        case duration
        case plainLyrics
        case syncedLyrics
    }
}

class LyricsService: ObservableObject {
    @Published var currentLyrics: LyricsResponse?
    @Published var isLoading = false
    @Published var error: String?
    
    private let session = URLSession.shared
    
    func fetchLyrics(title: String, artist: String) async {
        DispatchQueue.main.async {
            self.isLoading = true
            self.error = nil
        }
        
        do {
            let lyrics = try await searchLyrics(title: title, artist: artist)
            DispatchQueue.main.async {
                self.currentLyrics = lyrics
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func searchLyrics(title: String, artist: String) async throws -> LyricsResponse {
        // First try LRCLIB for synced lyrics
        if let lrclibLyrics = try? await fetchFromLRCLIB(title: title, artist: artist) {
            return lrclibLyrics
        }
        
        // Fallback to lyrics.ovh API (free, no API key required)
        let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let urlString = "https://api.lyrics.ovh/v1/\(encodedArtist)/\(encodedTitle)"
        
        guard let url = URL(string: urlString) else {
            throw LyricsError.invalidURL
        }
        
        let (data, _) = try await session.data(from: url)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let lyricsText = response?["lyrics"] as? String else {
            throw LyricsError.notFound
        }
        
        let lines = parsePlainTextLyrics(lyricsText)
        
        return LyricsResponse(
            title: title,
            artist: artist,
            lines: lines,
            isTimedLyrics: false
        )
    }
    
    private func fetchFromLRCLIB(title: String, artist: String) async throws -> LyricsResponse {
        // LRCLIB API - free, open-source, synced lyrics
        let baseURL = "https://lrclib.net/api/search"
        let query = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "\(baseURL)?q=\(query)"
        
        guard let url = URL(string: urlString) else {
            throw LyricsError.invalidURL
        }
        
        let (data, _) = try await session.data(from: url)
        let searchResults = try JSONDecoder().decode([LRCLIBSearchResult].self, from: data)
        
        // Find the best match
        guard let bestMatch = findBestMatch(searchResults: searchResults, targetTitle: title, targetArtist: artist) else {
            throw LyricsError.notFound
        }
        
        // Get detailed lyrics for the best match
        if let lyricsData = bestMatch.syncedLyrics {
            let lines = parseLRCLyrics(lyricsData)
            return LyricsResponse(
                title: bestMatch.trackName,
                artist: bestMatch.artistName,
                lines: lines,
                isTimedLyrics: true
            )
        } else if let plainLyrics = bestMatch.plainLyrics {
            let lines = parsePlainTextLyrics(plainLyrics)
            return LyricsResponse(
                title: bestMatch.trackName,
                artist: bestMatch.artistName,
                lines: lines,
                isTimedLyrics: false
            )
        }
        
        throw LyricsError.notFound
    }
    
    private func findBestMatch(searchResults: [LRCLIBSearchResult], targetTitle: String, targetArtist: String) -> LRCLIBSearchResult? {
        // Simple matching logic - can be enhanced later
        let normalizedTitle = targetTitle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = targetArtist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        return searchResults.first { result in
            let resultTitle = result.trackName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let resultArtist = result.artistName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            return resultTitle.contains(normalizedTitle) || normalizedTitle.contains(resultTitle) &&
                   resultArtist.contains(normalizedArtist) || normalizedArtist.contains(resultArtist)
        }
    }
    
    private func parseLRCLyrics(_ lrcContent: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        let lrcLines = lrcContent.components(separatedBy: .newlines)
        
        for line in lrcLines {
            // Parse LRC format: [mm:ss.xx]lyrics text
            let pattern = #"\[(\d{2}):(\d{2})\.(\d{2})\](.+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                continue
            }
            
            let minutes = Int(String(line[Range(match.range(at: 1), in: line)!])) ?? 0
            let seconds = Int(String(line[Range(match.range(at: 2), in: line)!])) ?? 0
            let centiseconds = Int(String(line[Range(match.range(at: 3), in: line)!])) ?? 0
            let text = String(line[Range(match.range(at: 4), in: line)!]).trimmingCharacters(in: .whitespaces)
            
            let startTime = Double(minutes * 60 + seconds) + Double(centiseconds) / 100.0
            let endTime = startTime + 4.0 // Default 4 second duration, will be adjusted later
            
            if !text.isEmpty {
                lines.append(LyricsLine(text: text, startTime: startTime, endTime: endTime))
            }
        }
        
        // Adjust end times based on next line start times
        for i in 0..<lines.count - 1 {
            lines[i] = LyricsLine(
                text: lines[i].text,
                startTime: lines[i].startTime,
                endTime: lines[i + 1].startTime
            )
        }
        
        return lines
    }
    
    private func parsePlainTextLyrics(_ text: String) -> [LyricsLine] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var lyricsLines: [LyricsLine] = []
        
        for (index, line) in lines.enumerated() {
            // Estimate timing: assume 3 seconds per line
            let startTime = Double(index) * 3.0
            let endTime = startTime + 3.0
            
            lyricsLines.append(LyricsLine(
                text: line,
                startTime: startTime,
                endTime: endTime
            ))
        }
        
        return lyricsLines
    }
    
    func getCurrentLine(at currentTime: Double) -> LyricsLine? {
        guard let lyrics = currentLyrics else { return nil }
        
        return lyrics.lines.first { line in
            currentTime >= line.startTime && currentTime < line.endTime
        }
    }
    
    func getUpcomingLines(from currentTime: Double, count: Int = 3) -> [LyricsLine] {
        guard let lyrics = currentLyrics else { return [] }
        
        return Array(lyrics.lines.filter { $0.startTime > currentTime }.prefix(count))
    }
}

enum LyricsError: Error {
    case notFound
    case invalidURL
    case networkError
    case parseError
    
    var localizedDescription: String {
        switch self {
        case .notFound:
            return "Lyrics not found"
        case .invalidURL:
            return "Invalid URL"
        case .networkError:
            return "Network error"
        case .parseError:
            return "Failed to parse lyrics"
        }
    }
}

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {
    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?

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

    // MARK: - Lyrics Integration
    @Published var lyricsService = LyricsService()
    @Published var currentLyricLine: String = ""
    @Published var isLyricsMode: Bool = false
    
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
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            // Initialize the active controller after deprecation check
            self.setActiveControllerBasedOnPreference()
        }
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()

        // Release active controller
        activeController = nil
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
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
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self,
                          self.activeController === controller else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]
        print("Preferred Media Controller: \(preferredType)")

        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType = (self.isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType

        if let controller = createController(for: controllerType) {
            setActiveController(controller)
        } else if controllerType != .appleMusic, let fallbackController = createController(for: .appleMusic) {
            // Fallback to Apple Music if preferred controller couldn't be created
            setActiveController(fallbackController)
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
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        print("📊 [MusicManager] Playback update - Playing: \(state.isPlaying), Time: \(state.currentTime)s, Duration: \(state.duration)s, Source: \(state.bundleIdentifier ?? "unknown")")
        
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
            // Fetch lyrics when track changes
            if !state.title.isEmpty && !state.artist.isEmpty {
                Task {
                    await self.lyricsService.fetchLyrics(title: state.title, artist: state.artist)
                }
            }
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if timeChanged {
            print("⏰ [MusicManager] Time updated: \(self.elapsedTime)s -> \(state.currentTime)s")
            self.elapsedTime = state.currentTime
            // Update current lyric line based on elapsed time
            if let currentLine = lyricsService.getCurrentLine(at: state.currentTime) {
                self.currentLyricLine = currentLine.text
            }
        } else {
            // Debug: Show current time even when not changing
            if state.isPlaying {
                print("🔄 [MusicManager] Playing but time not changing: \(state.currentTime)s (duration: \(state.duration)s)")
            }
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
                if  type(of: self?.activeController) == YouTubeMusicController.self,
                let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }
    
    // MARK: - Debug Methods
    
    func startLyricsDebugging() {
        print("🎵 [MusicManager] Starting simple lyrics debugging test...")
        Task {
            await testSpotifyAccessibility()
        }
    }
    
    private func testSpotifyAccessibility() async {
        print("🔍 [MusicManager] Testing comprehensive Spotify lyrics extraction...")
        
        // Check if accessibility is enabled
        let trusted = AXIsProcessTrusted()
        print("✅ [MusicManager] Accessibility trusted: \(trusted)")
        
        if !trusted {
            print("🔐 [MusicManager] Requesting accessibility permissions...")
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
            let _ = AXIsProcessTrustedWithOptions(options)
            print("⚠️ [MusicManager] Proceeding anyway for testing purposes...")
            // Continue execution despite permission issue
        }
        
        // Try to find Spotify
        let runningApps = NSWorkspace.shared.runningApplications
        guard let spotifyApp = runningApps.first(where: { $0.bundleIdentifier == "com.spotify.client" }) else {
            print("❌ [MusicManager] Spotify not found. Please open Spotify and try again.")
            return
        }
        
        print("✅ [MusicManager] Found Spotify (PID: \(spotifyApp.processIdentifier))")
        
        // Try AppleScript approach first (using existing Apple Events permissions)
        await tryAppleScriptLyricsExtraction()
        
        // Try accessibility approach as backup
        if trusted {
            await tryAccessibilityLyricsExtraction()
        } else {
            print("ℹ️ [MusicManager] Skipping accessibility extraction - permissions not granted")
        }
    }
    
    private func searchForLyricsInElement(_ element: AXUIElement, depth: Int, maxDepth: Int) {
        guard depth <= maxDepth else { return }
        
        let indent = String(repeating: "  ", count: depth)
        
        // Get element properties
        let role = getAccessibilityAttribute(element, attribute: kAXRoleAttribute as CFString) as? String ?? "unknown"
        let value = getAccessibilityAttribute(element, attribute: kAXValueAttribute as CFString) as? String
        let title = getAccessibilityAttribute(element, attribute: kAXTitleAttribute as CFString) as? String
        let description = getAccessibilityAttribute(element, attribute: kAXDescriptionAttribute as CFString) as? String
        let identifier = getAccessibilityAttribute(element, attribute: kAXIdentifierAttribute as CFString) as? String
        
        // Log interesting elements
        if depth <= 3 {
            print("🔍 \(indent)[\(depth)] Role: \(role)")
            if let identifier = identifier { print("🔍 \(indent)     ID: \(identifier)") }
            if let title = title, !title.isEmpty { print("🔍 \(indent)     Title: \(title)") }
            if let description = description, !description.isEmpty { print("🔍 \(indent)     Desc: \(description)") }
        }
        
        // Check if this element contains lyrics-like text
        if let lyricsText = analyzePotentialLyrics(role: role, value: value, title: title, description: description, identifier: identifier) {
            print("🎤 [MusicManager] === POTENTIAL LYRICS FOUND ===")
            print("🎤 [MusicManager] Element: \(role) (depth: \(depth))")
            print("🎤 [MusicManager] Text: \(lyricsText)")
            print("🎤 [MusicManager] ===============================")
        }
        
        // Search children
        if let children = getAccessibilityChildren(element) {
            for child in children {
                searchForLyricsInElement(child, depth: depth + 1, maxDepth: maxDepth)
            }
        }
    }
    
    private func analyzePotentialLyrics(role: String?, value: String?, title: String?, description: String?, identifier: String?) -> String? {
        let candidateTexts = [value, title, description].compactMap { $0 }
        
        for text in candidateTexts {
            if isLyricsText(text, role: role, identifier: identifier) {
                return text
            }
        }
        
        return nil
    }
    
    private func isLyricsText(_ text: String, role: String?, identifier: String?) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Must be substantial text
        guard trimmed.count > 15 else { return false }
        
        // Skip obvious UI elements
        let uiPatterns = [
            "spotify", "premium", "shuffle", "repeat", "volume", "play", "pause", "skip",
            "settings", "search", "library", "home", "browse", "queue", "devices",
            "connect", "install", "update", "subscribe", "menu", "button"
        ]
        
        let lowercaseText = trimmed.lowercased()
        for pattern in uiPatterns {
            if lowercaseText == pattern || (lowercaseText.contains(pattern) && trimmed.count < 50) {
                return false
            }
        }
        
        // Look for lyrics characteristics
        let hasMultipleWords = trimmed.components(separatedBy: .whitespaces).count >= 3
        let hasTypicalLength = trimmed.count >= 20 && trimmed.count <= 1000
        let hasLineBreaks = text.contains("\n")
        let hasPoetryPattern = trimmed.range(of: "\\b[A-Z][a-z]+\\s+[a-z]+", options: .regularExpression) != nil
        
        // Boost score for elements that might be lyrics containers
        let isLikelyLyricsContainer = 
            role?.lowercased().contains("text") == true ||
            identifier?.lowercased().contains("lyric") == true ||
            role?.lowercased().contains("scroll") == true
        
        let score = (hasMultipleWords ? 1 : 0) + 
                   (hasTypicalLength ? 1 : 0) + 
                   (hasLineBreaks ? 2 : 0) + 
                   (hasPoetryPattern ? 1 : 0) +
                   (isLikelyLyricsContainer ? 2 : 0)
        
        return score >= 3
    }
    
    private func getAccessibilityAttribute(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        return result == .success ? value : nil
    }
    
    private func getAccessibilityChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        
        guard result == .success, let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        
        return children
    }
    
    func stopLyricsDebugging() {
        print("🛑 [MusicManager] Stopping lyrics debugging...")
    }
    
    // MARK: - Alternative Lyrics Extraction Methods
    
    private func tryAppleScriptLyricsExtraction() async {
        print("🍎 [MusicManager] Trying AppleScript-based lyrics extraction...")
        
        // GEMINI_ASSISTANT: Bypassing the System Events script due to a persistent OS-level permission error.
        // The direct-to-Spotify communication is now working thanks to correct code signing.
        print("⚠️ [MusicManager] Bypassing System Events script.")
        await tryAppleScriptUIAccess()
    }
    
    private func tryAppleScriptUIAccess() async {
        print("🔍 [MusicManager] Searching for lyrics via direct Spotify AppleScript...")
        
        // First try to get current track info directly from Spotify
        let trackInfoScript = """
        tell application "Spotify"
            try
                set currentTrack to current track
                set trackName to name of currentTrack
                set artistName to artist of currentTrack
                set albumName to album of currentTrack
                return "Currently playing: " & trackName & " by " & artistName & " from " & albumName
            on error errMsg
                return "Spotify track info error: " & errMsg
            end try
        end tell
        """
        
        do {
            if let result = try await AppleScriptHelper.execute(trackInfoScript) {
                let trackInfo = result.stringValue ?? "No track info"
                print("🎵 [MusicManager] Track info: \(trackInfo)")
            }
        } catch {
            print("❌ [MusicManager] Track info script failed: \(error)")
        }
        
        // Comprehensive exploration of everything Spotify exposes through AppleScript
        let spotifyExplorationScript = """
        tell application "Spotify"
            try
                set explorationResult to ""
                
                -- Basic app info
                set appName to name
                set appVersion to version
                set explorationResult to explorationResult & "=== APP INFO ===" & return
                set explorationResult to explorationResult & "Name: " & appName & return
                set explorationResult to explorationResult & "Version: " & appVersion & return & return
                
                -- Player state
                set explorationResult to explorationResult & "=== PLAYER STATE ===" & return
                set playerState to player state
                set playerPosition to player position
                set shuffling to shuffling
                set repeating to repeating
                set soundVolume to sound volume
                set explorationResult to explorationResult & "State: " & playerState & return
                set explorationResult to explorationResult & "Position: " & playerPosition & return
                set explorationResult to explorationResult & "Shuffling: " & shuffling & return
                set explorationResult to explorationResult & "Repeating: " & repeating & return
                set explorationResult to explorationResult & "Volume: " & soundVolume & return & return
                
                -- Current track details
                set explorationResult to explorationResult & "=== CURRENT TRACK ===" & return
                set currentTrack to current track
                set trackName to name of currentTrack
                set artistName to artist of currentTrack
                set albumName to album of currentTrack
                set trackNumber to track number of currentTrack
                set discNumber to disc number of currentTrack
                set trackDuration to duration of currentTrack
                set trackId to spotify url of currentTrack
                set albumArtist to album artist of currentTrack
                set explorationResult to explorationResult & "Name: " & trackName & return
                set explorationResult to explorationResult & "Artist: " & artistName & return
                set explorationResult to explorationResult & "Album: " & albumName & return
                set explorationResult to explorationResult & "Album Artist: " & albumArtist & return
                set explorationResult to explorationResult & "Track Number: " & trackNumber & return
                set explorationResult to explorationResult & "Disc Number: " & discNumber & return
                set explorationResult to explorationResult & "Duration: " & trackDuration & return
                set explorationResult to explorationResult & "Spotify URL: " & trackId & return & return
                
                -- Try to explore if there are any other properties and their classes
                set explorationResult to explorationResult & "=== EXPLORING ALL PROPERTIES ===" & return
                try
                    set allProperties to properties of currentTrack
                    set explorationResult to explorationResult & "All track properties: " & allProperties & return
                    set explorationResult to explorationResult & "Properties class: " & (class of allProperties) & return
                on error propErr
                    set explorationResult to explorationResult & "Properties error: " & propErr & return
                end try
                
                -- Explore individual property classes
                set explorationResult to explorationResult & return & "=== PROPERTY CLASSES ===" & return
                try
                    set explorationResult to explorationResult & "Track name class: " & (class of trackName) & return
                    set explorationResult to explorationResult & "Artist class: " & (class of artistName) & return
                    set explorationResult to explorationResult & "Album class: " & (class of albumName) & return
                    set explorationResult to explorationResult & "Duration class: " & (class of trackDuration) & return
                    set explorationResult to explorationResult & "Track ID class: " & (class of trackId) & return
                    set explorationResult to explorationResult & "Current track class: " & (class of currentTrack) & return
                    set explorationResult to explorationResult & "Player state class: " & (class of playerState) & return
                on error classErr
                    set explorationResult to explorationResult & "Class exploration error: " & classErr & return
                end try
                
                -- Try to get artwork information with class exploration
                try
                    set artworkUrl to artwork url of currentTrack
                    set explorationResult to explorationResult & "Artwork URL: " & artworkUrl & return
                    set explorationResult to explorationResult & "Artwork URL class: " & (class of artworkUrl) & return
                    
                    -- Try to get artwork object itself (not just URL)
                    try
                        set artworkObj to artwork of currentTrack
                        set explorationResult to explorationResult & "Artwork object: " & artworkObj & return
                        set explorationResult to explorationResult & "Artwork object class: " & (class of artworkObj) & return
                    on error artObjErr
                        set explorationResult to explorationResult & "No artwork object: " & artObjErr & return
                    end try
                    
                on error artErr
                    set explorationResult to explorationResult & "No artwork URL available: " & artErr & return
                end try
                
                -- Check if there are any undocumented properties that might contain lyrics
                try
                    set explorationResult to explorationResult & return & "=== SEARCHING FOR LYRICS DATA ===" & return
                    -- Try common property names that might exist
                    try
                        set lyricsData to lyrics of currentTrack
                        set explorationResult to explorationResult & "FOUND LYRICS: " & lyricsData & return
                        set explorationResult to explorationResult & "LYRICS CLASS: " & (class of lyricsData) & return
                    on error lyricsErr
                        set explorationResult to explorationResult & "No 'lyrics' property: " & lyricsErr & return
                    end try
                    
                    try
                        set lyricsText to lyric of currentTrack
                        set explorationResult to explorationResult & "FOUND LYRIC: " & lyricsText & return
                        set explorationResult to explorationResult & "LYRIC CLASS: " & (class of lyricsText) & return
                    on error lyricErr
                        set explorationResult to explorationResult & "No 'lyric' property: " & lyricErr & return
                    end try
                    
                    try
                        set subtitle to subtitle of currentTrack
                        set explorationResult to explorationResult & "FOUND SUBTITLE: " & subtitle & return
                        set explorationResult to explorationResult & "SUBTITLE CLASS: " & (class of subtitle) & return
                    on error subtitleErr
                        set explorationResult to explorationResult & "No 'subtitle' property: " & subtitleErr & return
                    end try
                    
                    try
                        set description to description of currentTrack
                        set explorationResult to explorationResult & "FOUND DESCRIPTION: " & description & return
                        set explorationResult to explorationResult & "DESCRIPTION CLASS: " & (class of description) & return
                    on error descErr
                        set explorationResult to explorationResult & "No 'description' property: " & descErr & return
                    end try
                    
                    -- Try some additional potential lyrics properties
                    try
                        set trackText to text of currentTrack
                        set explorationResult to explorationResult & "FOUND TEXT: " & trackText & return
                        set explorationResult to explorationResult & "TEXT CLASS: " & (class of trackText) & return
                    on error textErr
                        set explorationResult to explorationResult & "No 'text' property: " & textErr & return
                    end try
                    
                    try
                        set trackContent to content of currentTrack
                        set explorationResult to explorationResult & "FOUND CONTENT: " & trackContent & return
                        set explorationResult to explorationResult & "CONTENT CLASS: " & (class of trackContent) & return
                    on error contentErr
                        set explorationResult to explorationResult & "No 'content' property: " & contentErr & return
                    end try
                    
                on error lyricSearchErr
                    set explorationResult to explorationResult & "Lyrics search error: " & lyricSearchErr & return
                end try
                
                return explorationResult
                
            on error mainErr
                return "Main exploration error: " & mainErr
            end try
        end tell
        """
        
        do {
            if let result = try await AppleScriptHelper.execute(spotifyExplorationScript) {
                let textInfo = result.stringValue ?? "No result"
                print("🎤 [MusicManager] Text content search result: \(textInfo)")
                
                // Analyze the found text for lyrics patterns
                if textInfo.contains("Found text content:") {
                    print("🎵 [MusicManager] === POTENTIAL LYRICS DETECTED ===")
                    print("🎵 [MusicManager] Content: \(textInfo)")
                    print("🎵 [MusicManager] ================================")
                }
            }
        } catch {
            print("❌ [MusicManager] AppleScript UI access failed: \(error)")
        }
    }
    
    private func tryAccessibilityLyricsExtraction() async {
        print("♿ [MusicManager] Trying direct accessibility extraction...")
        
        let runningApps = NSWorkspace.shared.runningApplications
        guard let spotifyApp = runningApps.first(where: { $0.bundleIdentifier == "com.spotify.client" }) else {
            return
        }
        
        let pid = spotifyApp.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
        
        if result == .success, let windows = windowsRef as? [AXUIElement] {
            print("✅ [MusicManager] Found \(windows.count) Spotify windows via accessibility")
            
            for (index, window) in windows.enumerated() {
                print("🔍 [MusicManager] === ACCESSIBILITY SEARCH WINDOW \(index + 1) ===")
                searchForLyricsInElement(window, depth: 0, maxDepth: 6)
            }
        } else {
            print("❌ [MusicManager] Accessibility extraction failed (result: \(result))")
        }
    }
    
    // MARK: - Lyrics Mode Functions
    
    func toggleLyricsMode() {
        withAnimation(.smooth) {
            isLyricsMode.toggle()
        }
        
        if isLyricsMode {
            print("🎵 [MusicManager] Lyrics mode enabled")
            
            // Force switch to Spotify controller for accurate timing
            print("🎵 [MusicManager] Switching to SpotifyController for accurate timing...")
            let spotifyController = SpotifyController()
            setActiveController(spotifyController)
            
            // Fetch lyrics for current track if available
            if !songTitle.isEmpty && !artistName.isEmpty {
                Task {
                    await lyricsService.fetchLyrics(title: songTitle, artist: artistName)
                    
                    // Force update playback info for timing
                    await spotifyController.updatePlaybackInfo()
                }
            }
        } else {
            print("🎵 [MusicManager] Lyrics mode disabled")
            // Restore original controller
            setActiveControllerBasedOnPreference()
        }
    }
    
    func startAutomaticLyricsTest() {
        print("🎵 [MusicManager] Starting automatic lyrics test...")
        if !songTitle.isEmpty && !artistName.isEmpty {
            print("🎵 [MusicManager] Testing lyrics for: \(songTitle) by \(artistName)")
            print("🎵 [MusicManager] Current elapsed time: \(Int(elapsedTime))s")
            
            // Enable lyrics mode first
            print("🎵 [MusicManager] Enabling lyrics mode...")
            isLyricsMode = true
            
            // Force switch to Spotify controller for accurate timing
            print("🎵 [MusicManager] Switching to SpotifyController for accurate timing...")
            let spotifyController = SpotifyController()
            setActiveController(spotifyController)
            
            Task {
                await lyricsService.fetchLyrics(title: songTitle, artist: artistName)
                
                // Update playback info after switching controller
                await spotifyController.updatePlaybackInfo()
                
                await MainActor.run {
                    print("🎵 [MusicManager] Lyrics service status - Loading: \(lyricsService.isLoading), Error: \(lyricsService.error ?? "none")")
                    if let lyrics = lyricsService.currentLyrics {
                        print("🎵 [MusicManager] Found \(lyrics.lines.count) lines of lyrics (Synced: \(lyrics.isTimedLyrics))")
                        print("🎵 [MusicManager] First few lines with timing:")
                        for (index, line) in lyrics.lines.prefix(5).enumerated() {
                            print("🎵 [MusicManager] Line \(index + 1): [\(line.startTime)s-\(line.endTime)s] \(line.text)")
                        }
                        
                        // Test current line lookup
                        if let currentLine = lyricsService.getCurrentLine(at: elapsedTime) {
                            print("🎵 [MusicManager] Current line at \(Int(elapsedTime))s: \(currentLine.text)")
                        } else {
                            print("🎵 [MusicManager] No current line found at \(Int(elapsedTime))s")
                        }
                        
                        print("🎵 [MusicManager] Updated elapsed time after controller switch: \(Int(elapsedTime))s")
                    } else {
                        print("🎵 [MusicManager] No lyrics found")
                    }
                }
            }
        } else {
            print("🎵 [MusicManager] No track info available for lyrics test")
        }
    }
}
