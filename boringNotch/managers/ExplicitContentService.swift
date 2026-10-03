//
//  ExplicitContentService.swift
//  boringNotch
//
//  Looks up parental-advisory / explicit tags for Apple Music tracks via the
//  public iTunes Search API (no auth / developer account required).
//

import Foundation

/// Parental-advisory style rating returned by the iTunes Search API.
enum TrackExplicitness: String, Sendable {
    case explicit
    case cleaned
    case notExplicit
}

/// Resolves explicitness for Apple Music tracks using Apple's public iTunes Search catalog.
final class ExplicitContentService {
    static let shared = ExplicitContentService()

    private final class CacheEntry {
        let isExplicit: Bool
        init(_ isExplicit: Bool) { self.isExplicit = isExplicit }
    }

    private let cache = NSCache<NSString, CacheEntry>()
    private let session: URLSession

    private init() {
        cache.countLimit = 200
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.httpShouldSetCookies = false
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    /// Returns whether the track should show an explicit badge.
    /// Only Apple Music is supported; other sources always return `false`.
    func resolve(
        bundleIdentifier: String?,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> Bool {
        guard let bundleIdentifier,
              bundleIdentifier == MediaAppBundleID.appleMusic
                || bundleIdentifier.contains(MediaAppBundleID.appleMusic),
              !title.isEmpty
        else {
            return false
        }

        let cacheKey = Self.cacheKey(title: title, artist: artist, album: album, duration: duration)
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached.isExplicit
        }

        let result = await fetchExplicitness(
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )
        cache.setObject(CacheEntry(result), forKey: cacheKey as NSString)
        return result
    }

    // MARK: - Networking

    private func fetchExplicitness(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> Bool {
        let query = [artist, title]
            .map(Self.normalized)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=25")
        else {
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("boringNotch/1.0 (macOS; explicit-tag)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }

            let decoded = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
            guard let best = Self.bestMatch(
                in: decoded.results,
                title: title,
                artist: artist,
                album: album,
                duration: duration
            ) else {
                return false
            }

            return Self.isExplicitPlayback(
                catalogExplicitness: best.trackExplicitness,
                playingTitle: title,
                playingAlbum: album
            )
        } catch {
            return false
        }
    }

    // MARK: - Matching

    /// iTunes Search often returns the *cleaned* catalog row for mainstream
    /// songs and almost never `"explicit"`. Treat `cleaned` as “this song has
    /// an explicit edition”, unless the now-playing title/album is clearly the
    /// clean edit (e.g. contains "(Clean)").
    static func isExplicitPlayback(
        catalogExplicitness: TrackExplicitness?,
        playingTitle: String,
        playingAlbum: String
    ) -> Bool {
        switch catalogExplicitness {
        case .explicit:
            return true
        case .cleaned:
            return !looksLikeCleanEdit(title: playingTitle, album: playingAlbum)
        case .notExplicit, .none:
            return false
        }
    }

    static func looksLikeCleanEdit(title: String, album: String) -> Bool {
        let haystack = "\(title) \(album)".lowercased()
        let markers = ["(clean)", "[clean]", " clean version", "- clean", "clean edit"]
        return markers.contains { haystack.contains($0) }
    }

    static func bestMatch(
        in results: [iTunesSearchTrack],
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) -> iTunesSearchTrack? {
        guard !results.isEmpty else { return nil }

        let normalizedTitle = normalized(title)
        let normalizedArtist = normalized(artist)
        let normalizedAlbum = normalized(album)

        var best: (track: iTunesSearchTrack, score: Int)?

        for result in results {
            let score = matchScore(
                result: result,
                title: normalizedTitle,
                artist: normalizedArtist,
                album: normalizedAlbum,
                duration: duration
            )
            // Require at least a title + artist signal so we don't badge random hits.
            guard score >= 12 else { continue }
            if best == nil || score > best!.score {
                best = (result, score)
            }
        }

        return best?.track
    }

    static func matchScore(
        result: iTunesSearchTrack,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) -> Int {
        var score = 0

        let resultTitle = normalized(result.trackName ?? "")
        let resultArtist = normalized(result.artistName ?? "")
        let resultAlbum = normalized(result.collectionName ?? "")

        if !title.isEmpty, !resultTitle.isEmpty {
            if resultTitle == title {
                score += 10
            } else if resultTitle.contains(title) || title.contains(resultTitle) {
                score += 5
            }
        }

        if !artist.isEmpty, !resultArtist.isEmpty {
            if resultArtist == artist {
                score += 8
            } else if resultArtist.contains(artist) || artist.contains(resultArtist) {
                score += 4
            }
        }

        if !album.isEmpty, !resultAlbum.isEmpty {
            if resultAlbum == album {
                score += 5
            } else if resultAlbum.contains(album) || album.contains(resultAlbum) {
                score += 2
            }
        }

        if duration > 0, let millis = result.trackTimeMillis {
            let delta = abs((Double(millis) / 1000.0) - duration)
            if delta <= 2 {
                score += 15
            } else if delta <= 5 {
                score += 8
            } else if delta <= 12 {
                score += 3
            }
        }

        return score
    }

    static func normalized(_ string: String) -> String {
        string
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cacheKey(title: String, artist: String, album: String, duration: TimeInterval) -> String {
        let roundedDuration = Int(duration.rounded())
        return "\(normalized(title))|\(normalized(artist))|\(normalized(album))|\(roundedDuration)"
    }
}

// MARK: - iTunes Search models

struct iTunesSearchResponse: Decodable, Sendable {
    let resultCount: Int
    let results: [iTunesSearchTrack]
}

struct iTunesSearchTrack: Decodable, Sendable, Equatable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let trackTimeMillis: Int?
    let trackExplicitnessRaw: String?

    var trackExplicitness: TrackExplicitness? {
        trackExplicitnessRaw.flatMap(TrackExplicitness.init(rawValue:))
    }

    private enum CodingKeys: String, CodingKey {
        case trackName
        case artistName
        case collectionName
        case trackTimeMillis
        case trackExplicitnessRaw = "trackExplicitness"
    }
}
