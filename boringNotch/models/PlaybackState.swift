//
//  PlaybackState.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

enum RepeatMode: Int, Codable {
    case off = 1
    case one = 2
    case all = 3
}

struct PlaybackState {
    var bundleIdentifier: String
    var audioCaptureBundleIdentifiers: [String] = []
    var trackIdentifier: String?
    var capabilities: MediaCapabilities?
    var isPlaying: Bool = false
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var currentTime: Double = 0
    var duration: Double = 0
    var playbackRate: Double = 1
    var isShuffled: Bool = false
    var repeatMode: RepeatMode = .off
    var lastUpdated: Date = Date.distantPast
    var artwork: Data?
    var volume: Double = 0.5
    var isFavorite: Bool = false

    // The adapter does not expose a stable track ID. Metadata identity is the
    // fallback; artwork and playback position never participate in identity.
    var identity: PlaybackIdentity {
        PlaybackIdentity(source: normalizeBundleIdentifier(bundleIdentifier).lowercased(),
                         track: trackIdentifier.map { [$0] } ?? [title, artist, album])
    }

    mutating func applyArtwork(_ data: Data, for identity: PlaybackIdentity) {
        guard self.identity == identity else { return }
        artwork = data
    }

    var effectiveAudioCaptureBundleIdentifiers: [String] {
        let raw = audioCaptureBundleIdentifiers.isEmpty ? [bundleIdentifier] : audioCaptureBundleIdentifiers
        return raw.normalizedBundleIdentifiers
    }
}

extension Sequence where Element == String {
    var normalizedBundleIdentifiers: [String] {
        var seen = Set<String>()
        return filter { value in
            guard !value.isEmpty, !seen.contains(value) else { return false }
            seen.insert(value)
            return true
        }
    }
}

extension PlaybackState: Equatable {
    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        return lhs.identity == rhs.identity
            && lhs.capabilities == rhs.capabilities
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.effectiveAudioCaptureBundleIdentifiers == rhs.effectiveAudioCaptureBundleIdentifiers
            && lhs.isPlaying == rhs.isPlaying
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.currentTime == rhs.currentTime
            && lhs.duration == rhs.duration
            && lhs.isShuffled == rhs.isShuffled
            && lhs.repeatMode == rhs.repeatMode
            && lhs.artwork == rhs.artwork
            && lhs.isFavorite == rhs.isFavorite
    }
}

func normalizeBundleIdentifier(_ bundleID: String) -> String {
    let lower = bundleID.lowercased()

    // Handle Safari Technology Preview rendering helper processes
    if lower.hasPrefix("com.apple.safaritechnologypreview.") {
        return "com.apple.SafariTechnologyPreview"
    }

    // Handle WebKit / Safari rendering helper processes
    if lower.hasPrefix("com.apple.webkit.") || lower.hasPrefix("com.apple.safari.") {
        return "com.apple.Safari"
    }

    // General rule for Chromium/Electron helper processes
    // e.g., "com.google.Chrome.helper" -> "com.google.Chrome"
    let components = bundleID.components(separatedBy: ".")
    if let helperIndex = components.firstIndex(where: { $0.lowercased() == "helper" }) {
        return components[0..<helperIndex].joined(separator: ".")
    }

    return bundleID
}

struct PlaybackIdentity: Equatable {
    let source: String
    let track: [String]
}

struct MediaCapabilities: Equatable {
    var favorite = false
    var shuffle = false
    var repeatModes: [RepeatMode] = []

    static let unsupported = MediaCapabilities()
    static let appleMusic = MediaCapabilities(favorite: true, shuffle: true, repeatModes: [.off, .all, .one])
    // Spotify's scripting dictionary only has a Boolean `repeating` property.
    static let spotify = MediaCapabilities(shuffle: true, repeatModes: [.off, .all])

    func nextRepeatMode(after mode: RepeatMode) -> RepeatMode? {
        guard repeatModes.count > 1 else { return nil }
        guard let index = repeatModes.firstIndex(of: mode) else { return repeatModes.first }
        return repeatModes[(index + 1) % repeatModes.count]
    }
}

/// Seconds must fit the exact integer domain shared by formatting and seeking.
/// This preserves long podcasts/books without inventing a song-length limit;
/// extreme finite values outside that domain display as unavailable.
enum PlaybackTime {
    static let maximumSeconds = 9_007_199_254_740_991.0

    static func valid(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= maximumSeconds
    }

    static func sanitized(_ value: Double) -> Double { valid(value) ? value : 0 }

    static func seekRange(duration: Double) -> ClosedRange<Double>? {
        valid(duration) && duration > 0 ? 0...duration : nil
    }

    static func position(elapsed: Double, duration: Double, rate: Double,
                         playing: Bool, sampledAt: Date, now: Date) -> Double {
        let elapsed = sanitized(elapsed)
        let delta = now.timeIntervalSince(sampledAt)
        let advance = playing && valid(rate) && valid(delta) ? delta * rate : 0
        let estimate = sanitized(elapsed + advance)
        return seekRange(duration: duration).map { min(estimate, $0.upperBound) } ?? estimate
    }

    static func relativeSeekTarget(seconds: Double, elapsed: Double, duration: Double,
                                   rate: Double, playing: Bool, sampledAt: Date, now: Date) -> Double? {
        guard seconds.isFinite, let range = seekRange(duration: duration) else { return nil }
        let current = position(elapsed: elapsed, duration: duration, rate: rate,
                               playing: playing, sampledAt: sampledAt, now: now)
        return min(max(0, current + seconds), range.upperBound)
    }

    static func string(from seconds: Double) -> String {
        guard valid(seconds) else { return "--:--" }
        let total = Int64(seconds)
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        let suffix = String(format: "%02lld:%02lld", minutes, seconds)
        return hours > 0 ? "\(hours):\(suffix)" : String(format: "%lld:%02lld", minutes, seconds)
    }
}

struct NowPlayingUpdate: Codable, Sendable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Codable, Sendable {
    var presentFields: Set<String> = []
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
    let volume: Double?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case title, artist, album, duration, elapsedTime, shuffleMode, repeatMode, artworkData, timestamp, playbackRate, playing, parentApplicationBundleIdentifier, bundleIdentifier, volume
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presentFields = Set(container.allKeys.map(\.rawValue))
        title = try container.decodeIfPresent(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        album = try container.decodeIfPresent(String.self, forKey: .album)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        elapsedTime = try container.decodeIfPresent(Double.self, forKey: .elapsedTime)
        shuffleMode = try container.decodeIfPresent(Int.self, forKey: .shuffleMode)
        repeatMode = try container.decodeIfPresent(Int.self, forKey: .repeatMode)
        artworkData = try container.decodeIfPresent(String.self, forKey: .artworkData)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate)
        playing = try container.decodeIfPresent(Bool.self, forKey: .playing)
        parentApplicationBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .parentApplicationBundleIdentifier)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        volume = try container.decodeIfPresent(Double.self, forKey: .volume)
    }
}

extension NowPlayingUpdate {
    func applying(to previous: PlaybackState, receivedAt now: Date = Date()) -> PlaybackState {
        let p = payload
        let isDiff = diff == true
        let source = normalizeBundleIdentifier(p.parentApplicationBundleIdentifier ?? p.bundleIdentifier ?? (isDiff ? previous.bundleIdentifier : ""))
        let sameSource = source.lowercased() == previous.identity.source
        let metadataChanged = (p.title.map { $0 != previous.title } ?? p.presentFields.contains("title"))
            || (p.artist.map { $0 != previous.artist } ?? p.presentFields.contains("artist"))
            || (p.album.map { $0 != previous.album } ?? p.presentFields.contains("album"))
        let keep = isDiff && sameSource && !metadataChanged
        func field<T>(_ name: String, _ value: T?, _ old: T, _ empty: T) -> T {
            value ?? (keep && !p.presentFields.contains(name) ? old : empty)
        }
        var state = keep ? previous : PlaybackState(bundleIdentifier: source)
        state.bundleIdentifier = source
        state.audioCaptureBundleIdentifiers = p.bundleIdentifier.map { [$0] }
            ?? (isDiff && sameSource ? previous.effectiveAudioCaptureBundleIdentifiers : [source])
        state.title = field("title", p.title, previous.title, "")
        state.artist = field("artist", p.artist, previous.artist, "")
        state.album = field("album", p.album, previous.album, "")
        state.duration = PlaybackTime.sanitized(field("duration", p.duration, previous.duration, 0))
        state.isPlaying = p.playing ?? (isDiff && sameSource && !p.presentFields.contains("playing") ? previous.isPlaying : false)
        state.playbackRate = PlaybackTime.sanitized(field("playbackRate", p.playbackRate, previous.playbackRate, 1))
        state.isShuffled = field("shuffleMode", p.shuffleMode.map { $0 != 1 }, previous.isShuffled, false)
        state.repeatMode = field("repeatMode", p.repeatMode.flatMap(RepeatMode.init(rawValue:)), previous.repeatMode, .off)
        state.volume = min(1, PlaybackTime.sanitized(p.volume ?? (isDiff && sameSource && !p.presentFields.contains("volume") ? previous.volume : 0.5)))
        if let artwork = p.artworkData {
            state.artwork = Data(base64Encoded: artwork.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if !keep || p.presentFields.contains("artworkData") {
            state.artwork = nil
        }
        // Receipt time anchors accepted position samples even when the numeric
        // elapsed value repeats (restart-to-zero or two tracks at position zero).
        let timingChanged = !keep || p.presentFields.contains("elapsedTime") || p.elapsedTime != nil
            || p.presentFields.contains("timestamp") || state.duration != previous.duration
            || state.isPlaying != previous.isPlaying || state.playbackRate != previous.playbackRate
        if timingChanged {
            if let elapsed = p.elapsedTime {
                state.currentTime = PlaybackTime.sanitized(elapsed)
            } else if keep && !p.presentFields.contains("elapsedTime") {
                state.currentTime = PlaybackTime.position(elapsed: previous.currentTime, duration: previous.duration,
                    rate: previous.playbackRate, playing: previous.isPlaying, sampledAt: previous.lastUpdated, now: now)
            } else {
                state.currentTime = 0
            }
            state.lastUpdated = p.elapsedTime != nil
                ? p.timestamp.flatMap { ISO8601DateFormatter().date(from: $0) } ?? now : now
        }
        if let range = PlaybackTime.seekRange(duration: state.duration) {
            state.currentTime = min(state.currentTime, range.upperBound)
        }
        // Only advertise source modes actually observed on this identity.
        let knownSource = source == "com.apple.Music" || source == "com.spotify.client"
        var capabilities = keep ? previous.capabilities ?? .unsupported : .unsupported
        if !knownSource { capabilities = .unsupported }
        if knownSource && (p.shuffleMode != nil || p.presentFields.contains("shuffleMode") || !keep) {
            capabilities.shuffle = p.shuffleMode != nil
        }
        if knownSource && (p.repeatMode != nil || p.presentFields.contains("repeatMode") || !keep) {
            capabilities.repeatModes = p.repeatMode == nil ? [] : (source == "com.spotify.client" ? [.off, .all] : [.off, .all, .one])
        }
        state.capabilities = capabilities
        return state
    }
}
