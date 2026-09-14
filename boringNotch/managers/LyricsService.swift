//
//  LyricsService.swift
//  boringNotch
//
//  Extracted from MusicManager for better separation of concerns.
//

import AppKit
import Foundation
import Combine

/// Service responsible for fetching and parsing lyrics for the currently playing track.
@MainActor
final class LyricsService: ObservableObject {
    static let shared = LyricsService()
    
    @Published var currentLyrics: String = ""
    @Published var isFetchingLyrics: Bool = false
    @Published var syncedLyrics: [(time: Double, text: String)] = []
    
    // Cache to avoid redundant fetches; NSCache evicts under memory pressure
    // instead of growing for the whole session.
    private final class LyricsEntry {
        let plain: String
        let synced: [(time: Double, text: String)]
        init(plain: String, synced: [(time: Double, text: String)]) {
            self.plain = plain
            self.synced = synced
        }
    }
    private final class Track: NSObject {
        let bundleIdentifier: String?
        let title: String
        let artist: String

        init(bundleIdentifier: String?, title: String, artist: String) {
            self.bundleIdentifier = bundleIdentifier
            self.title = title
            self.artist = artist
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(bundleIdentifier)
            hasher.combine(title)
            hasher.combine(artist)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Track else { return false }
            return bundleIdentifier == other.bundleIdentifier && title == other.title && artist == other.artist
        }
    }

    typealias LyricsResult = (plain: String, synced: [(time: Double, text: String)])
    typealias NativeFetcher = @MainActor (String, String) async -> String?
    typealias WebFetcher = @MainActor (String, String) async -> LyricsResult

    private let lyricsCache = NSCache<Track, LyricsEntry>()
    private var currentFetchTask: Task<Void, Never>?
    private var requestID = UUID()
    private let nativeFetcher: NativeFetcher
    private let webFetcher: WebFetcher

    init(nativeFetcher: NativeFetcher? = nil, webFetcher: WebFetcher? = nil) {
        self.nativeFetcher = nativeFetcher ?? Self.fetchAppleMusicLyrics
        self.webFetcher = webFetcher ?? Self.fetchLyricsFromWeb
    }
    
    // MARK: - Public API
    
    /// Prefer synchronized lyrics; keep native plain text visible during web lookup.
    func fetchLyrics(bundleIdentifier: String?, title: String, artist: String) async {
        currentFetchTask?.cancel()
        let id = UUID()
        requestID = id
        guard !title.isEmpty else {
            clearLyrics()
            return
        }

        let track = Track(bundleIdentifier: bundleIdentifier, title: title, artist: artist)
        if let cached = lyricsCache.object(forKey: track) {
            currentLyrics = cached.plain
            syncedLyrics = cached.synced
            isFetchingLyrics = false
            return
        }

        isFetchingLyrics = true
        currentLyrics = ""
        syncedLyrics = []

        let task = Task { [weak self] in
            guard let self else { return }
            var nativePlain = ""
            if bundleIdentifier == MediaAppBundleID.appleMusic {
                nativePlain = await self.nativeFetcher(title, artist) ?? ""
                guard !Task.isCancelled, self.requestID == id else { return }
                let nativeSynced = Self.parseLRC(nativePlain)
                self.currentLyrics = nativePlain
                if !nativeSynced.isEmpty {
                    self.syncedLyrics = nativeSynced
                    self.isFetchingLyrics = false
                    self.lyricsCache.setObject(LyricsEntry(plain: nativePlain, synced: nativeSynced), forKey: track)
                    return
                }
            }

            guard !Task.isCancelled, self.requestID == id else { return }
            let web = await self.webFetcher(title, artist)
            guard !Task.isCancelled, self.requestID == id else { return }

            let plain = !web.synced.isEmpty ? web.plain : (nativePlain.isEmpty ? web.plain : nativePlain)
            self.currentLyrics = plain
            self.syncedLyrics = web.synced
            self.isFetchingLyrics = false
            // Do not cache a failed lookup that only retained native plain text:
            // a later visit to this track should be able to find synchronized lyrics.
            if !web.plain.isEmpty || !web.synced.isEmpty {
                self.lyricsCache.setObject(LyricsEntry(plain: plain, synced: web.synced), forKey: track)
            }
        }

        currentFetchTask = task
        await task.value
    }

    /// Clears all lyrics data.
    func clearLyrics() {
        currentFetchTask?.cancel()
        currentFetchTask = nil
        requestID = UUID()
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

        // Binary search for last line with time <= elapsed
        var low = 0
        var high = syncedLyrics.count - 1
        var idx = 0
        while low <= high {
            let mid = (low + high) / 2
            if syncedLyrics[mid].time <= elapsed {
                idx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let nextIndex = syncedLyrics.index(after: idx)
        let endTime = nextIndex < syncedLyrics.endIndex ? syncedLyrics[nextIndex].time : nil
        return (syncedLyrics[idx].text, syncedLyrics[idx].time, endTime)
    }
    
    // MARK: - Private Methods
    
    private static func fetchAppleMusicLyrics(title: String, artist: String) async -> String? {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: MediaAppBundleID.appleMusic)
        guard !runningApps.isEmpty else { return nil }
        
        let script = """
        tell application "Music"
            if it is running then
                if player state is playing or player state is paused then
                    try
                        set sourceTrack to current track
                        set l to lyrics of sourceTrack
                        if l is missing value then
                            return ""
                        else
                            return {name of sourceTrack, artist of sourceTrack, l}
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
            if let result = try await AppleScriptHelper.execute(script),
               let sourceTitle = result.atIndex(1)?.stringValue,
               let sourceArtist = result.atIndex(2)?.stringValue,
               normalizedQuery(sourceTitle) == normalizedQuery(title),
               normalizedQuery(sourceArtist) == normalizedQuery(artist),
               let lyricsString = result.atIndex(3)?.stringValue,
               !lyricsString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return lyricsString.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // Fall through to return nil
        }
        return nil
    }
    
    private static func fetchLyricsFromWeb(title: String, artist: String) async -> (plain: String, synced: [(time: Double, text: String)]) {
        let cleanTitle = normalizedQuery(title)
        let cleanArtist = normalizedQuery(artist)
        
        guard let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return ("", [])
        }
        
        // Try with artist first, then without if no results
        let searchStrategies: [String] = {
            var strategies: [String] = []
            
            // Strategy 1: Search with artist (if provided)
            if !cleanArtist.isEmpty,
               let encodedArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                strategies.append("https://lrclib.net/api/search?track_name=\(encodedTitle)&artist_name=\(encodedArtist)")
            }
            
            // Strategy 2: Search with title only (always include as fallback)
            strategies.append("https://lrclib.net/api/search?track_name=\(encodedTitle)")
            
            return strategies
        }()
        
        for urlString in searchStrategies {
            guard !Task.isCancelled else { return ("", []) }
            guard let url = URL(string: urlString) else { continue }
            
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    continue
                }
                
                if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let first = findBestMatch(in: jsonArray, title: cleanTitle, artist: cleanArtist) {
                    let plain = (first["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let synced = (first["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    if !plain.isEmpty || !synced.isEmpty {
                        let resolvedPlain = plain.isEmpty ? synced : plain
                        let parsedSynced = synced.isEmpty ? [] : parseLRC(synced)
                        return (resolvedPlain, parsedSynced)
                    }
                }
            } catch {
                continue
            }
        }
        
        return ("", [])
    }
    
    /// Find the best matching result from the search results based on title similarity
    private static func findBestMatch(in results: [[String: Any]], title: String, artist: String) -> [String: Any]? {
        guard !results.isEmpty else { return nil }
        
        // If only one result, use it
        if results.count == 1 { return results.first }
        
        let normalizedTitle = title.lowercased()
        let normalizedArtist = artist.lowercased()
        
        // Score each result and pick the best
        var bestResult: [String: Any]? = nil
        var bestScore = 0
        
        for result in results {
            var score = 0
            
            // Check title match
            if let resultTitle = result["trackName"] as? String {
                if resultTitle.lowercased() == normalizedTitle {
                    score += 10
                } else if resultTitle.lowercased().contains(normalizedTitle) || normalizedTitle.contains(resultTitle.lowercased()) {
                    score += 5
                }
            }
            
            // Check artist match (bonus if provided and matches)
            if !normalizedArtist.isEmpty, let resultArtist = result["artistName"] as? String {
                if resultArtist.lowercased() == normalizedArtist {
                    score += 8
                } else if resultArtist.lowercased().contains(normalizedArtist) || normalizedArtist.contains(resultArtist.lowercased()) {
                    score += 4
                }
            }
            
            // Prefer results with lyrics
            if let plain = result["plainLyrics"] as? String, !plain.isEmpty {
                score += 2
            }
            if let synced = result["syncedLyrics"] as? String, !synced.isEmpty {
                score += 3
            }
            
            if score > bestScore {
                bestScore = score
                bestResult = result
            }
        }
        
        return bestResult ?? results.first
    }
    
    // MARK: - Synced lyrics helpers
    
    private static func parseLRC(_ lrc: String) -> [(time: Double, text: String)] {
        var result: [(Double, String)] = []
        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        for lineSub in lrc.split(separator: "\n") {
            let line = String(lineSub)
            let nsLine = line as NSString
            
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
                continue
            }
            
            let minStr = nsLine.substring(with: match.range(at: 1))
            let secStr = nsLine.substring(with: match.range(at: 2))
            let msRange = match.range(at: 3)
            let msStr = msRange.location != NSNotFound ? nsLine.substring(with: msRange) : "0"
            
            let minutes = Double(minStr) ?? 0
            let seconds = Double(secStr) ?? 0
            guard seconds < 60 else { continue }
            // LRC fractions may contain one, two or three decimal digits.
            let msValue = Double(msStr) ?? 0
            let msDivisor = pow(10.0, Double(msStr.count))
            let time = minutes * 60 + seconds + msValue / msDivisor
            
            let textStart = match.range.location + match.range.length
            let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                result.append((time, text))
            }
        }
        
        return result.sorted { $0.0 < $1.0 }
    }
    
    private static func normalizedQuery(_ string: String) -> String {
        string
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
