//
//  KasetController.swift
//  boringNotch
//
//  AppleScript-based controller for Kaset (https://github.com/sozercan/kaset),
//  a native macOS YouTube Music client. Modeled on AppleMusicController /
//  SpotifyController: it reads and controls Kaset through its AppleScript suite
//  (`get player info`, transport commands, `like track`). Favourite is supported
//  because Kaset exposes per-track like state, just like Apple Music's `favorited`.
//
//  Kaset's bundle id and AppleScript dictionary are fixed, so no configuration is
//  required. State is refreshed on a short poll and, when available, on Kaset's
//  `com.sertacozercan.Kaset.playerInfo` distributed notification.
//

import AppKit
import Combine
import Foundation
import ImageIO
import SwiftUI

class KasetController: MediaControllerProtocol {
    // MARK: - Properties
    @Published private var playbackState = PlaybackState(
        bundleIdentifier: KasetController.bundleIdentifier
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool { true }
    var supportsFavorite: Bool { true }

    private static let bundleIdentifier = "com.sertacozercan.Kaset"
    private static let changeNotification = NSNotification.Name("com.sertacozercan.Kaset.playerInfo")
    private static let pollInterval: TimeInterval = 2.0

    private var notificationTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var artworkFetchTask: Task<Void, Never>?
    /// Identity (videoId, else artworkURL) of the track whose cover is loaded or in flight — so
    /// repeated polls don't refetch. Reset on track change / failure so the cover can (re)load.
    private var lastArtworkKey: String?

    // MARK: - Initialization
    init() {
        setupPlaybackStateChangeObserver()
        startPolling()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }

    deinit {
        notificationTask?.cancel()
        artworkFetchTask?.cancel()
        pollTimer?.invalidate()
    }

    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: KasetController.changeNotification
            )
            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        // Kaset is sandboxed; its distributed notification may not be delivered on
        // every system, so poll as a reliable baseline (the notification just makes
        // updates snappier when it does arrive).
        pollTimer = Timer.scheduledTimer(withTimeInterval: KasetController.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Call unconditionally: updatePlaybackInfo handles the inactive case
                // (it clears state), so this is how we notice Kaset quitting.
                await self.updatePlaybackInfo()
            }
        }
    }

    // MARK: - Protocol Implementation
    func play() async { await executeCommand("play") }
    func pause() async { await executeCommand("pause") }
    func togglePlay() async { await executeCommand("playpause") }
    func nextTrack() async { await executeCommand("next track") }
    func previousTrack() async { await executeCommand("previous track") }

    func seek(to time: Double) async {
        await executeCommand("seek \(time)")
        await refreshSoon()
    }

    func toggleShuffle() async {
        await executeCommand("toggle shuffle")
        await refreshSoon()
    }

    func toggleRepeat() async {
        await executeCommand("cycle repeat")
        await refreshSoon()
    }

    func setVolume(_ level: Double) async {
        let percentage = Int((max(0.0, min(1.0, level)) * 100).rounded())
        await executeCommand("set volume \(percentage)")
        await refreshSoon()
    }

    @MainActor
    func setFavorite(_ favorite: Bool) async {
        // Kaset's `like track` toggles; only send it when the state actually flips.
        // @MainActor-isolated so this `isFavorite` read shares the isolation domain
        // that writes playbackState (applyPlayerInfo), avoiding a data race.
        guard favorite != playbackState.isFavorite else { return }
        await executeCommand("like track")
        await refreshSoon()
    }

    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == KasetController.bundleIdentifier
        }
    }

    func updatePlaybackInfo() async {
        guard isActive() else {
            // Kaset isn't running; clear any stale track so the notch doesn't keep
            // showing a phantom Kaset song after the app quits.
            await resetPlaybackState()
            return
        }
        guard let descriptor = try? await AppleScriptHelper.execute(
                  "tell application \"Kaset\" to get player info"
              ),
              let json = descriptor.stringValue,
              let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        await applyPlayerInfo(object)
    }

    // MARK: - Private Methods

    // Main-actor isolated so the poll timer and the distributed-notification
    // observer (which run on different executors) can't mutate state concurrently.
    @MainActor
    private func applyPlayerInfo(_ object: [String: Any]) {
        var state = playbackState

        let track = object["currentTrack"] as? [String: Any]
        let newTitle = (track?["name"] as? String) ?? "Not Playing"
        let newArtist = (track?["artist"] as? String) ?? ""
        let newAlbum = (track?["album"] as? String) ?? ""
        // A new track is starting if any identity field changed. `state` is copied from the
        // previous `playbackState`, so without this we'd carry the OLD track's cover into the
        // new track's published state.
        let trackChanged = newTitle != playbackState.title
            || newArtist != playbackState.artist
            || newAlbum != playbackState.album

        state.isPlaying = (object["isPlaying"] as? Bool) ?? false
        state.title = newTitle
        state.artist = newArtist
        state.album = newAlbum
        state.currentTime = Self.double(object["position"]) ?? 0
        state.duration = Self.double(object["duration"]) ?? Self.double(track?["duration"]) ?? 0
        state.isShuffled = (object["shuffling"] as? Bool) ?? false
        state.repeatMode = Self.repeatMode(object["repeating"] as? String)
        if let volume = Self.double(object["volume"]) { state.volume = volume / 100.0 }
        state.isFavorite = (object["likeStatus"] as? String) == "liked"
        state.lastUpdated = Date()

        if trackChanged {
            // Don't publish the previous track's cover under the new track. MusicManager gates
            // its "content changed" bookkeeping on the artwork, so a stale non-nil cover makes it
            // re-fire the sneak peek and flip animation on every 2s poll until fresh art arrives
            // (forever if the fetch fails). Clearing lets it settle immediately (app icon shows
            // until the real cover loads); fetchArtworkIfNeeded repopulates below.
            state.artwork = nil
            lastArtworkKey = nil
        }

        if state != playbackState {
            playbackState = state
        }

        fetchArtworkIfNeeded(
            artworkURL: track?["artworkURL"] as? String,
            videoId: track?["videoId"] as? String
        )
    }

    @MainActor
    private func fetchArtworkIfNeeded(artworkURL: String?, videoId: String?) {
        // Kaset's `get player info` usually reports a useless artworkURL (the YouTube Music
        // homepage), but always gives a videoId. Derive the cover from YouTube's thumbnail
        // endpoint in that case; prefer a real image artworkURL when Kaset does provide one.
        let key = videoId ?? artworkURL
        guard let key, !key.isEmpty, key != lastArtworkKey else { return }
        let candidates = Self.artworkCandidateURLs(artworkURL: artworkURL, videoId: videoId)
        guard !candidates.isEmpty else { return }
        // Mark in-flight so repeated polls don't restart a healthy fetch.
        lastArtworkKey = key
        artworkFetchTask?.cancel()
        artworkFetchTask = Task { [weak self] in
            for url in candidates {
                if Task.isCancelled { return }
                guard let data = try? await ImageService.shared.fetchImageData(from: url),
                      let square = Self.squareJPEGData(from: data) else { continue }
                if Task.isCancelled { return }
                await MainActor.run { [weak self] in
                    guard let self, self.lastArtworkKey == key else { return }
                    self.playbackState.artwork = square
                }
                return
            }
            // No candidate produced a valid image — forget the key so the next poll retries
            // instead of sticking on the app-icon fallback.
            await MainActor.run { [weak self] in
                guard let self, self.lastArtworkKey == key else { return }
                self.lastArtworkKey = nil
            }
        }
    }

    /// Ordered cover URLs to try: a genuine image artworkURL first (Kaset rarely provides one),
    /// then YouTube thumbnails derived from the videoId. The homepage/app-internal URL Kaset
    /// usually reports is filtered out.
    private static func artworkCandidateURLs(artworkURL: String?, videoId: String?) -> [URL] {
        var urls: [URL] = []
        if let artworkURL, !artworkURL.isEmpty,
           let url = URL(string: artworkURL),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
           let host = url.host, host != "music.youtube.com" {
            urls.append(url)
        }
        if let videoId, !videoId.isEmpty {
            for name in ["maxresdefault", "hqdefault"] {
                if let url = URL(string: "https://i.ytimg.com/vi/\(videoId)/\(name).jpg") {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    /// Decode `data`, center-crop to a square, and re-encode as JPEG. Returns nil if the bytes
    /// aren't a decodable image (doubles as validation). YouTube thumbnails are 16:9/4:3; the
    /// notch shows cover art with `.fit`, so a square keeps it from rendering as a wide strip.
    private static func squareJPEGData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        let side = min(width, height)
        let cropRect = CGRect(
            x: (width - side) / 2, y: (height - side) / 2, width: side, height: side
        )
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cropped)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }

    @MainActor
    private func resetPlaybackState() {
        artworkFetchTask?.cancel()
        lastArtworkKey = nil
        let cleared = PlaybackState(bundleIdentifier: KasetController.bundleIdentifier, isPlaying: false)
        if cleared != playbackState {
            playbackState = cleared
        }
    }

    private func executeCommand(_ command: String) async {
        try? await AppleScriptHelper.executeVoid("tell application \"Kaset\" to \(command)")
    }

    private func refreshSoon() async {
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func repeatMode(_ value: String?) -> RepeatMode {
        switch value {
        case "all": .all
        case "one": .one
        default: .off
        }
    }
}
