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
    
    // Cache to avoid redundant fetches
    private var lyricsCache: [String: (plain: String, synced: [(time: Double, text: String)])] = [:]
    private var currentFetchTask: Task<Void, Never>?
    
    private init() {}
    
    // MARK: - Public API
    
    /// Fetches lyrics for the given track, preferring native Apple Music lyrics when available.
    func fetchLyrics(bundleIdentifier: String?, title: String, artist: String) async {
        // Cancel any pending fetch
        currentFetchTask?.cancel()
        
        guard !title.isEmpty else {
            clearLyrics()
            return
        }
        
        // Check cache first
        let cacheKey = cacheKey(title: title, artist: artist)
        if let cached = lyricsCache[cacheKey] {
            currentLyrics = cached.plain
            syncedLyrics = cached.synced
            isFetchingLyrics = false
            return
        }
        
        isFetchingLyrics = true
        currentLyrics = ""
        syncedLyrics = []
        
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            // Try Apple Music first if applicable
            if let bundleIdentifier = bundleIdentifier, bundleIdentifier.contains("com.apple.Music") {
                if let lyrics = await self.fetchAppleMusicLyrics() {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self.currentLyrics = lyrics
                        self.syncedLyrics = []
                        self.isFetchingLyrics = false
                        self.lyricsCache[cacheKey] = (plain: lyrics, synced: [])
                    }
                    return
                }
            }
            
            // Fallback to web
            guard !Task.isCancelled else { return }
            let webResult = await self.fetchLyricsFromWeb(title: title, artist: artist)
            
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.currentLyrics = webResult.plain
                self.syncedLyrics = webResult.synced
                self.isFetchingLyrics = false
                if !webResult.plain.isEmpty {
                    self.lyricsCache[cacheKey] = webResult
                }
            }
        }
        
        currentFetchTask = task
        await task.value
    }
    
    /// Clears all lyrics data.
    func clearLyrics() {
        currentFetchTask?.cancel()
        currentFetchTask = nil
        currentLyrics = ""
        syncedLyrics = []
        isFetchingLyrics = false
    }
    
    /// Returns the lyric line at the given elapsed time for synced lyrics.
    func lyricLine(at elapsed: Double) -> String {
        guard !syncedLyrics.isEmpty else { return currentLyrics }
        
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
        return syncedLyrics[idx].text
    }
    
    // MARK: - Private Methods
    
    private func cacheKey(title: String, artist: String) -> String {
        "\(normalizedQuery(title))|\(normalizedQuery(artist))"
    }
    
    private func fetchAppleMusicLyrics() async -> String? {
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
            if let result = try await AppleScriptHelper.execute(script),
               let lyricsString = result.stringValue,
               !lyricsString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return lyricsString.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // Fall through to return nil
        }
        return nil
    }
    
    private func fetchLyricsFromWeb(title: String, artist: String) async -> (plain: String, synced: [(time: Double, text: String)]) {
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
    private func findBestMatch(in results: [[String: Any]], title: String, artist: String) -> [String: Any]? {
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
    
    private func parseLRC(_ lrc: String) -> [(time: Double, text: String)] {
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
            // Handle both centiseconds (2 digits) and milliseconds (3 digits)
            let msValue = Double(msStr) ?? 0
            let msDivisor = msStr.count == 3 ? 1000.0 : 100.0
            let time = minutes * 60 + seconds + msValue / msDivisor
            
            let textStart = match.range.location + match.range.length
            let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                result.append((time, text))
            }
        }
        
        return result.sorted { $0.0 < $1.0 }
    }
    
    private func normalizedQuery(_ string: String) -> String {
        string
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
