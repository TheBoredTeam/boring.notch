//
//  LyricsService.swift
//  boringNotch
//
//  Extracted from MusicManager for better separation of concerns.
//

import AppKit
import Foundation

/// Service responsible for fetching and parsing lyrics for the currently playing track.
@MainActor
class LyricsService: ObservableObject {
    static let shared = LyricsService()

    @Published var currentLyrics: String = ""
    @Published var isFetchingLyrics: Bool = false
    @Published var syncedLyrics: [(time: Double, text: String)] = []

    private struct LyricsRequest {
        let bundleIdentifier: String?
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
    }

    private struct LyricsPayload {
        let plain: String
        let synced: String

        var isEmpty: Bool {
            plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private struct CachedLyrics {
        let plain: String
        let synced: [(time: Double, text: String)]
    }

    private enum LyricsLookupResult {
        case found(LyricsPayload)
        case notFound
        case transientFailure(retryAfter: TimeInterval?)
        case cancelled
    }

    private let maximumCacheEntries = 100
    private var lyricsCache: [String: CachedLyrics] = [:]
    private var cacheOrder: [String] = []
    private var currentFetchTask: Task<Void, Never>?
    private var requestGeneration: UInt = 0
    private var activeRequestKey: String?

    private init() {}

    // MARK: - Public API

    /// Fetches lyrics using the native player when possible, then the configured web providers.
    func fetchLyrics(
        bundleIdentifier: String?,
        title: String,
        artist: String,
        album: String = "",
        duration: TimeInterval = 0
    ) async {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearLyrics()
            return
        }

        let request = LyricsRequest(
            bundleIdentifier: bundleIdentifier,
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )
        let requestKey = lyricsRequestKey(request)
        let alreadyHasLyrics = !currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !syncedLyrics.isEmpty

        // Artwork and playback-position updates often repeat identical metadata.
        if requestKey == activeRequestKey, isFetchingLyrics || alreadyHasLyrics {
            return
        }

        currentFetchTask?.cancel()
        requestGeneration &+= 1
        let generation = requestGeneration
        activeRequestKey = requestKey

        // Never leave the previous track's lyrics visible while a new lookup is running.
        currentLyrics = ""
        syncedLyrics = []
        isFetchingLyrics = false

        if let cached = cachedLyrics(for: requestKey) {
            currentLyrics = cached.plain
            syncedLyrics = cached.synced
            return
        }

        isFetchingLyrics = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if generation == self.requestGeneration {
                    self.currentFetchTask = nil
                }
            }

            // Media providers may publish title, album, duration, and artwork separately.
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard self.isCurrentRequest(generation) else { return }

            let payload = await self.resolveLyrics(for: request)
            guard self.isCurrentRequest(generation) else { return }

            if let payload, !payload.isEmpty {
                self.publish(payload, cacheKey: requestKey)
            } else {
                self.currentLyrics = ""
                self.syncedLyrics = []
            }
            self.isFetchingLyrics = false
        }

        currentFetchTask = task
        await task.value
    }

    /// Clears all lyric state and invalidates any in-flight provider response.
    func clearLyrics() {
        currentFetchTask?.cancel()
        currentFetchTask = nil
        requestGeneration &+= 1
        activeRequestKey = nil
        currentLyrics = ""
        syncedLyrics = []
        isFetchingLyrics = false
    }

    /// Returns the lyric line at the given elapsed time for synced lyrics.
    func lyricLine(at elapsed: Double) -> String {
        lyricLineContext(at: elapsed).text
    }

    /// Returns the active synced lyric line and its timing window.
    func lyricLineContext(at elapsed: Double) -> (text: String, startTime: Double, endTime: Double?) {
        guard !syncedLyrics.isEmpty else { return (currentLyrics, 0, nil) }
        guard elapsed >= syncedLyrics[0].time else {
            return ("", 0, syncedLyrics[0].time)
        }

        var low = 0
        var high = syncedLyrics.count - 1
        var index = 0
        while low <= high {
            let middle = (low + high) / 2
            if syncedLyrics[middle].time <= elapsed {
                index = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }

        let nextIndex = syncedLyrics.index(after: index)
        let endTime = nextIndex < syncedLyrics.endIndex ? syncedLyrics[nextIndex].time : nil
        return (syncedLyrics[index].text, syncedLyrics[index].time, endTime)
    }

    // MARK: - Request lifecycle

    private func isCurrentRequest(_ generation: UInt) -> Bool {
        generation == requestGeneration && !Task.isCancelled
    }

    private func lyricsRequestKey(_ request: LyricsRequest) -> String {
        let roundedDuration = request.duration > 0 ? Int(request.duration.rounded()) : 0
        return [
            request.bundleIdentifier ?? "",
            normalizedMatchValue(request.title),
            normalizedMatchValue(request.artist),
            normalizedMatchValue(request.album),
            String(roundedDuration)
        ].joined(separator: "|")
    }

    private func cachedLyrics(for key: String) -> CachedLyrics? {
        guard let cached = lyricsCache[key] else { return nil }
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        return cached
    }

    private func publish(_ payload: LyricsPayload, cacheKey: String) {
        let parsedSynced = payload.synced.isEmpty ? [] : parseLRC(payload.synced)
        let generatedPlain = parsedSynced.map(\.text).joined(separator: "\n")
        let plain = payload.plain.isEmpty
            ? (generatedPlain.isEmpty ? payload.synced : generatedPlain)
            : payload.plain

        currentLyrics = plain
        syncedLyrics = parsedSynced
        lyricsCache[cacheKey] = CachedLyrics(plain: plain, synced: parsedSynced)
        cacheOrder.removeAll { $0 == cacheKey }
        cacheOrder.append(cacheKey)

        while cacheOrder.count > maximumCacheEntries {
            let evictedKey = cacheOrder.removeFirst()
            lyricsCache.removeValue(forKey: evictedKey)
        }
    }

    private func retryAfterDelay(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(value)
    }

    private func failureResult(for response: HTTPURLResponse) -> LyricsLookupResult {
        switch response.statusCode {
        case 404:
            return .notFound
        case 408, 425, 429, 500 ... 599:
            return .transientFailure(retryAfter: retryAfterDelay(from: response))
        default:
            return .notFound
        }
    }

    private func fetchLyricsWithRetry(
        provider: String,
        maxAttempts: Int = 2,
        operation: () async -> LyricsLookupResult
    ) async -> LyricsLookupResult {
        var attempt = 1

        while true {
            guard !Task.isCancelled else { return .cancelled }
            let result = await operation()

            switch result {
            case .found, .notFound, .cancelled:
                return result
            case let .transientFailure(retryAfter):
                guard attempt < maxAttempts else {
                    NSLog("Lyrics: %@ failed after %d attempt(s)", provider, attempt)
                    return result
                }

                let delay = min(max(retryAfter ?? 0.5, 0.25), 5)
                NSLog("Lyrics: retrying %@ in %.2f seconds", provider, delay)
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return .cancelled
                }
                attempt += 1
            }
        }
    }

    private func resolveLyrics(for request: LyricsRequest) async -> LyricsPayload? {
        if request.bundleIdentifier?.contains("com.apple.Music") == true,
           let nativeLyrics = await fetchAppleMusicLyrics() {
            NSLog("Lyrics: using native Apple Music lyrics")
            return nativeLyrics
        }

        let providers: [(String, () async -> LyricsLookupResult)] = [
            ("LRCLIB", { await self.fetchLyricsFromLRCLIB(request: request) }),
            ("lrcmux", { await self.fetchLyricsFromLRCMux(request: request) }),
            ("NetEase", { await self.fetchLyricsFromNetEase(request: request) })
        ]

        for (provider, lookup) in providers {
            guard !Task.isCancelled else { return nil }
            let result = await fetchLyricsWithRetry(provider: provider, operation: lookup)
            switch result {
            case let .found(payload):
                NSLog("Lyrics: using %@ result", provider)
                return payload
            case .notFound:
                NSLog("Lyrics: %@ found no strict match for %@ — %@", provider, request.title, request.artist)
            case .transientFailure:
                NSLog("Lyrics: %@ unavailable; continuing to next provider", provider)
            case .cancelled:
                return nil
            }
        }
        return nil
    }

    // MARK: - Native Apple Music

    private func fetchAppleMusicLyrics() async -> LyricsPayload? {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return nil }

        let script = """
        tell application "Music"
            if it is running then
                if player state is playing or player state is paused then
                    try
                        set l to lyrics of current track
                        if l is missing value then
                            return ""
                        else
                            return l
                        end if
                    on error
                        return ""
                    end try
                else
                    return ""
                end if
            else
                return ""
            end if
        end tell
        """

        do {
            guard let result = try await AppleScriptHelper.execute(script),
                  let lyrics = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !lyrics.isEmpty else { return nil }
            return LyricsPayload(plain: lyrics, synced: "")
        } catch {
            NSLog("Lyrics: Apple Music lookup failed: %@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - LRCLIB

    private func fetchLyricsFromLRCLIB(request: LyricsRequest) async -> LyricsLookupResult {
        let cleanTitle = normalizedQuery(request.title)
        let cleanArtist = normalizedQuery(request.artist)
        var strategies: [[URLQueryItem]] = []

        if !cleanArtist.isEmpty {
            strategies.append([
                URLQueryItem(name: "track_name", value: cleanTitle),
                URLQueryItem(name: "artist_name", value: cleanArtist)
            ])
        }
        strategies.append([URLQueryItem(name: "track_name", value: cleanTitle)])

        for queryItems in strategies {
            guard let url = makeURL("https://lrclib.net/api/search", queryItems: queryItems) else {
                return .transientFailure(retryAfter: nil)
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: webRequest(url: url))
                guard let http = response as? HTTPURLResponse else {
                    return .transientFailure(retryAfter: nil)
                }
                guard http.statusCode == 200 else {
                    let failure = failureResult(for: http)
                    if case .notFound = failure { continue }
                    return failure
                }
                guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    return .transientFailure(retryAfter: nil)
                }
                if let payload = bestLRCLIBPayload(in: results, request: request) {
                    return .found(payload)
                }
            } catch {
                if Task.isCancelled { return .cancelled }
                NSLog("Lyrics: LRCLIB request failed: %@", error.localizedDescription)
                return .transientFailure(retryAfter: nil)
            }
        }

        return .notFound
    }

    private func bestLRCLIBPayload(
        in results: [[String: Any]],
        request: LyricsRequest
    ) -> LyricsPayload? {
        let targetTitle = normalizedMatchValue(request.title)
        let targetAlbum = normalizedMatchValue(request.album)
        var best: (score: Double, payload: LyricsPayload)?

        for result in results {
            guard let candidateTitle = result["trackName"] as? String,
                  normalizedMatchValue(candidateTitle) == targetTitle,
                  let candidateArtist = result["artistName"] as? String,
                  artistMatches(candidateArtist, request.artist) else { continue }

            let candidateAlbum = normalizedMatchValue((result["albumName"] as? String) ?? "")
            let albumMatches = !targetAlbum.isEmpty && candidateAlbum == targetAlbum
            let candidateDuration = (result["duration"] as? NSNumber)?.doubleValue ?? 0
            let hasDurationEvidence = request.duration > 0 && candidateDuration > 0
            let durationDelta = hasDurationEvidence ? abs(candidateDuration - request.duration) : 0

            guard !hasDurationEvidence || durationDelta <= 8 else { continue }
            if request.duration > 0, candidateDuration <= 0, !targetAlbum.isEmpty, !albumMatches {
                continue
            }

            let plain = (result["plainLyrics"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let synced = (result["syncedLyrics"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let payload = LyricsPayload(plain: plain, synced: synced)
            guard !payload.isEmpty else { continue }

            let score = durationDelta
                + (targetAlbum.isEmpty || albumMatches ? 0 : 20)
                + (synced.isEmpty ? 2 : 0)
            if best == nil || score < best!.score {
                best = (score, payload)
            }
        }
        return best?.payload
    }

    // MARK: - lrcmux

    private func fetchLyricsFromLRCMux(request: LyricsRequest) async -> LyricsLookupResult {
        var queryItems = [
            URLQueryItem(name: "title", value: normalizedQuery(request.title)),
            URLQueryItem(name: "artist", value: normalizedQuery(request.artist)),
            URLQueryItem(name: "level", value: "line"),
            URLQueryItem(name: "format", value: "lrc"),
            // LRCLIB was queried directly, so do not repeat it through lrcmux.
            URLQueryItem(name: "sources", value: "!lrclib")
        ]
        if !request.album.isEmpty {
            queryItems.append(URLQueryItem(name: "album", value: normalizedQuery(request.album)))
        }
        if request.duration > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(request.duration.rounded()))))
        }

        guard let url = makeURL("https://api.lrcmux.dev/get", queryItems: queryItems) else {
            return .transientFailure(retryAfter: nil)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: webRequest(url: url))
            guard let http = response as? HTTPURLResponse else {
                return .transientFailure(retryAfter: nil)
            }
            guard http.statusCode == 200 else { return failureResult(for: http) }
            guard let lyrics = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !lyrics.isEmpty else { return .notFound }

            let source = http.value(forHTTPHeaderField: "X-Source") ?? "unknown"
            let cache = http.value(forHTTPHeaderField: "X-Cache") ?? "unknown"
            let syncLevel = http.value(forHTTPHeaderField: "X-Sync-Level") ?? "none"
            NSLog("Lyrics: lrcmux source=%@ cache=%@ sync=%@", source, cache, syncLevel)

            let parsedLines = parseLRC(lyrics)
            if syncLevel == "none" || parsedLines.isEmpty {
                return .found(LyricsPayload(plain: lyrics, synced: ""))
            }

            let plain = parsedLines.map(\.text).joined(separator: "\n")
            return .found(LyricsPayload(plain: plain, synced: lyrics))
        } catch {
            if Task.isCancelled { return .cancelled }
            NSLog("Lyrics: lrcmux request failed: %@", error.localizedDescription)
            return .transientFailure(retryAfter: nil)
        }
    }

    // MARK: - NetEase fallback

    private func fetchLyricsFromNetEase(request: LyricsRequest) async -> LyricsLookupResult {
        // NetEase does not publish these endpoints as a stable third-party API.
        // Keep it as a best-effort final fallback with strict metadata matching.
        guard !normalizedMatchValue(request.artist).isEmpty else { return .notFound }
        guard let searchURL = makeURL(
            "https://music.163.com/api/search/get",
            queryItems: [
                URLQueryItem(name: "s", value: "\(request.title) \(request.artist)"),
                URLQueryItem(name: "type", value: "1"),
                URLQueryItem(name: "limit", value: "10"),
                URLQueryItem(name: "offset", value: "0")
            ]
        ) else { return .transientFailure(retryAfter: nil) }

        do {
            let (data, response) = try await URLSession.shared.data(for: netEaseRequest(url: searchURL))
            guard let http = response as? HTTPURLResponse else {
                return .transientFailure(retryAfter: nil)
            }
            guard http.statusCode == 200 else { return failureResult(for: http) }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["code"] as? NSNumber)?.intValue == 200,
                  let result = root["result"] as? [String: Any],
                  let songs = result["songs"] as? [[String: Any]] else {
                return .transientFailure(retryAfter: nil)
            }

            guard !Task.isCancelled else { return .cancelled }
            guard let songID = bestNetEaseSongID(in: songs, request: request) else {
                return .notFound
            }
            guard let lyricsURL = makeURL(
                "https://music.163.com/api/song/lyric",
                queryItems: [
                    URLQueryItem(name: "id", value: String(songID)),
                    URLQueryItem(name: "lv", value: "1"),
                    URLQueryItem(name: "kv", value: "1"),
                    URLQueryItem(name: "tv", value: "-1")
                ]
            ) else { return .transientFailure(retryAfter: nil) }

            let (lyricsData, lyricsResponse) = try await URLSession.shared.data(
                for: netEaseRequest(url: lyricsURL)
            )
            guard let lyricsHTTP = lyricsResponse as? HTTPURLResponse else {
                return .transientFailure(retryAfter: nil)
            }
            guard lyricsHTTP.statusCode == 200 else { return failureResult(for: lyricsHTTP) }
            guard let lyricsRoot = try JSONSerialization.jsonObject(with: lyricsData) as? [String: Any],
                  (lyricsRoot["code"] as? NSNumber)?.intValue == 200,
                  let lrc = lyricsRoot["lrc"] as? [String: Any],
                  let synced = (lrc["lyric"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !synced.isEmpty else { return .notFound }

            let plain = parseLRC(synced).map(\.text).joined(separator: "\n")
            return .found(LyricsPayload(plain: plain, synced: synced))
        } catch {
            if Task.isCancelled { return .cancelled }
            NSLog("Lyrics: NetEase request failed: %@", error.localizedDescription)
            return .transientFailure(retryAfter: nil)
        }
    }

    private func bestNetEaseSongID(
        in songs: [[String: Any]],
        request: LyricsRequest
    ) -> Int64? {
        let targetTitle = normalizedMatchValue(request.title)
        let targetAlbum = normalizedMatchValue(request.album)
        var bestMatch: (id: Int64, score: Double)?

        for song in songs {
            guard let id = (song["id"] as? NSNumber)?.int64Value,
                  let name = song["name"] as? String,
                  normalizedMatchValue(name) == targetTitle,
                  let artists = song["artists"] as? [[String: Any]],
                  artists.contains(where: { artist in
                      guard let name = artist["name"] as? String else { return false }
                      return artistMatches(name, request.artist)
                  }) else { continue }

            let albumName = ((song["album"] as? [String: Any])?["name"] as? String) ?? ""
            let albumMatches = !targetAlbum.isEmpty && normalizedMatchValue(albumName) == targetAlbum
            let candidateDuration = (song["duration"] as? NSNumber)?.doubleValue ?? 0
            let hasDurationEvidence = request.duration > 0 && candidateDuration > 0
            let durationDelta = hasDurationEvidence ? abs(candidateDuration / 1000 - request.duration) : 0

            // Require either close duration or exact album evidence beyond title and artist.
            guard (!hasDurationEvidence || durationDelta <= 8),
                  hasDurationEvidence || albumMatches else { continue }
            let score = durationDelta + (albumMatches ? 0 : 30)
            if bestMatch == nil || score < bestMatch!.score {
                bestMatch = (id, score)
            }
        }
        return bestMatch?.id
    }

    // MARK: - Helpers

    private func webRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "boringNotch (https://github.com/TheBoredTeam/boring.notch)",
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }

    private func netEaseRequest(url: URL) -> URLRequest {
        var request = webRequest(url: url)
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        return request
    }

    private func makeURL(_ baseURL: String, queryItems: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.queryItems = queryItems
        return components.url
    }

    private func normalizedQuery(_ string: String) -> String {
        string
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedMatchValue(_ string: String) -> String {
        normalizedQuery(string)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func artistMatches(_ candidateArtist: String, _ targetArtist: String) -> Bool {
        let candidate = normalizedMatchValue(candidateArtist)
        let target = normalizedMatchValue(targetArtist)
        if target.isEmpty { return true }
        guard !candidate.isEmpty else { return false }
        return candidate == target || candidate.contains(target) || target.contains(candidate)
    }

    private func parseLRC(_ lrc: String) -> [(time: Double, text: String)] {
        var result: [(Double, String)] = []
        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for lineSubstring in lrc.split(separator: "\n") {
            let line = String(lineSubstring)
            let nsLine = line as NSString
            guard let match = regex.firstMatch(
                in: line,
                range: NSRange(location: 0, length: nsLine.length)
            ) else { continue }

            let minutes = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
            let seconds = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
            let fractionRange = match.range(at: 3)
            let fractionString = fractionRange.location == NSNotFound
                ? ""
                : nsLine.substring(with: fractionRange)
            let fraction = Double(fractionString) ?? 0
            let divisor = pow(10, Double(fractionString.count))
            let time = minutes * 60 + seconds
                + (fractionString.isEmpty ? 0 : fraction / divisor)
            let textStart = match.range.location + match.range.length
            let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                result.append((time, text))
            }
        }

        return result.sorted { $0.0 < $1.0 }
    }
}
