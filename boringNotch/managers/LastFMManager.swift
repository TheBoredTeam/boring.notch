//
//  LastFMManager.swift
//  boringNotch
//
//  Manages last.fm authentication, now-playing updates and scrobbling.
//  Hooks into MusicManager's playback state updates to automatically
//  scrobble tracks when they reach the last.fm scrobbling threshold.
//

import Foundation
import Defaults

/// last.fm API credentials and session are configured via Settings.
/// Users must provide their own API key/secret from https://www.last.fm/api/account
actor LastFMManager {
    static let shared = LastFMManager()
    
    // MARK: - Configuration
    
    private let baseURL = "https://ws.audioscrobbler.com/2.0/"
    
    /// API key obtained from last.fm (set in Settings)
    private var apiKey: String { Defaults[.lastFmAPIKey] }
    /// API secret obtained from last.fm (set in Settings)
    private var apiSecret: String { Defaults[.lastFmAPISecret] }
    
    // MARK: - Session
    
    private var sessionKey: String? {
        get { Defaults[.lastFmSessionKey] }
        set { Defaults[.lastFmSessionKey] = newValue }
    }
    
    private var username: String? {
        get { Defaults[.lastFmUsername] }
        set { Defaults[.lastFmUsername] = newValue }
    }
    
    func isAuthenticated() async -> Bool {
        !(sessionKey?.isEmpty ?? true)
    }
    
    var currentUsername: String? { username }
    
    private init() {}
    
    // MARK: - Authentication flow
    
    /// Step 1: request a temporary token from last.fm.
    func requestToken() async throws -> String {
        guard !apiKey.isEmpty else {
            throw LastFMError.apiError("last.fm API key is not set in Settings")
        }
        
        let params: [String: String] = [
            "method": "auth.getToken",
            "api_key": apiKey,
            "format": "json"
        ]
        let response: LastFMTokenResponse = try await signedRequest(params: params, responseType: LastFMTokenResponse.self)
        return response.token
    }
    
    /// Builds the authorization URL the user should open in a browser.
    func authorizationURL(for token: String) async -> URL? {
        var components = URLComponents(string: "https://www.last.fm/api/auth/")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "token", value: token)
        ]
        return components?.url
    }
    
    /// Step 3: exchange the authorized token for a session key.
    func fetchSession(token: String) async throws -> LastFMSessionResponse {
        let params: [String: String] = [
            "method": "auth.getSession",
            "api_key": apiKey,
            "token": token,
            "format": "json"
        ]
        let response: LastFMSessionResponse = try await signedRequest(params: params, responseType: LastFMSessionResponse.self)
        return response
    }
    
    /// Persists the session after successful authentication.
    func storeSession(_ response: LastFMSessionResponse) async {
        sessionKey = response.session.key
        username = response.session.name
        // Reset scrobbling state for the new session
        currentTrack = nil
        trackStartTime = nil
        hasScrobbledCurrentTrack = false
        hasUpdatedNowPlaying = false
    }
    
    /// Clears the stored session (sign out).
    func signOut() async {
        sessionKey = nil
        username = nil
        currentTrack = nil
        trackStartTime = nil
        hasScrobbledCurrentTrack = false
        hasUpdatedNowPlaying = false
    }
    
    /// Test scrobble for debugging
    func testScrobble(
        artist: String,
        title: String,
        album: String,
        duration: TimeInterval,
        timestamp: Int
    ) async {
        await scrobble(artist: artist, title: title, album: album, duration: duration, timestamp: timestamp)
    }
    
    // MARK: - Scrobbling state
    
    /// Information about the track currently being tracked for scrobbling.
    private var currentTrack: (artist: String, title: String, album: String, duration: TimeInterval)?
    /// When the current track started playing.
    private var trackStartTime: Date?
    /// Whether the current track has already been scrobbled.
    private var hasScrobbledCurrentTrack = false
    /// Whether `updateNowPlaying` has already been sent for the current track.
    private var hasUpdatedNowPlaying = false
    
    /// Call this whenever the playback state changes (from MusicManager).
    /// Handles now-playing updates and automatic scrobbling.
    func handlePlaybackUpdate(
        isPlaying: Bool,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        currentTime: TimeInterval
    ) async {
        guard await isAuthenticated() else { return }
        guard !title.isEmpty, !artist.isEmpty else { return }
        
        let trackChanged = currentTrack?.title != title || currentTrack?.artist != artist
        
        if trackChanged {
            // --- Previous track: scrobble if not yet scrobbled and played long enough ---
            if let previous = currentTrack, !hasScrobbledCurrentTrack, let start = trackStartTime {
                let elapsed = Date().timeIntervalSince(start)
                if LastFMScrobblePolicy.shouldScrobble(duration: previous.duration, elapsed: elapsed) {
                    Task {
                        await scrobble(
                            artist: previous.artist,
                            title: previous.title,
                            album: previous.album,
                            duration: previous.duration,
                            timestamp: Int(start.timeIntervalSince1970)
                        )
                    }
                }
            }
            
            // --- New track: start tracking ---
            currentTrack = (artist: artist, title: title, album: album, duration: duration)
            trackStartTime = Date()
            hasScrobbledCurrentTrack = false
            hasUpdatedNowPlaying = false
            
            // Report "now playing" to last.fm
            Task {
                await updateNowPlaying(
                    artist: artist,
                    title: title,
                    album: album,
                    duration: duration
                )
            }
        } else if isPlaying && !hasScrobbledCurrentTrack, let start = trackStartTime {
            // --- Same track still playing: check if scrobbling threshold reached ---
            let elapsed = Date().timeIntervalSince(start)
            if LastFMScrobblePolicy.shouldScrobble(duration: duration, elapsed: elapsed) {
                hasScrobbledCurrentTrack = true
                Task {
                    await scrobble(
                        artist: artist,
                        title: title,
                        album: album,
                        duration: duration,
                        timestamp: Int(start.timeIntervalSince1970)
                    )
                }
            }
        }
    }
    
    // MARK: - API calls
    
    /// Notifies last.fm that a track is currently playing.
    private func updateNowPlaying(artist: String, title: String, album: String, duration: TimeInterval) async {
        guard await isAuthenticated(), !hasUpdatedNowPlaying else { return }
        hasUpdatedNowPlaying = true
        
        let params: [String: String] = [
            "method": "track.updateNowPlaying",
            "api_key": apiKey,
            "sk": sessionKey!,
            "artist": artist,
            "track": title,
            "album": album,
            "format": "json"
        ]
        
        do {
            _ = try await signedRequest(params: params, responseType: EmptyResponse.self, method: "POST")
            print("[LastFM] Now playing: \(artist) - \(title)")
        } catch {
            print("[LastFM] updateNowPlaying error: \(error)")
        }
    }
    
    /// Scrobbles a track to last.fm.
    private func scrobble(
        artist: String,
        title: String,
        album: String,
        duration: TimeInterval,
        timestamp: Int
    ) async {
        guard await isAuthenticated() else { return }
        
        let params: [String: String] = [
            "method": "track.scrobble",
            "api_key": apiKey,
            "sk": sessionKey!,
            "artist[0]": artist,
            "track[0]": title,
            "album[0]": album,
            "duration[0]": String(Int(duration)),
            "timestamp[0]": String(timestamp),
            "format": "json"
        ]
        
        do {
            _ = try await signedRequest(params: params, responseType: EmptyResponse.self, method: "POST")
            print("[LastFM] Scrobbled: \(artist) - \(title) (ts: \(timestamp))")
        } catch {
            print("[LastFM] Scrobble error: \(error)")
        }
    }
    
    // MARK: - Networking
    
    /// Decodable struct for last.fm error responses
    private struct LastFMErrorResponse: Decodable {
        let error: Int
        let message: String
    }
    
    /// Decodable struct for last.fm error wrapped in "error" key (some responses use this format)
    private struct LastFMWrappedErrorResponse: Decodable {
        let error: LastFMErrorResponse
    }
    
    private func signedRequest<T: Decodable>(params: [String: String], responseType: T.Type = EmptyResponse.self, method: String = "GET") async throws -> T {
        var allParams = params
        allParams["api_sig"] = apiSignature(params: allParams)
        
        var components = URLComponents(string: baseURL)
        components?.queryItems = allParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = components?.url else {
            throw LastFMError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        if method == "POST" {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            // For POST, put params in body, not query string
            let bodyString = allParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)" }.joined(separator: "&")
            request.httpBody = bodyString.data(using: .utf8)
            // Remove query from URL for POST
            components?.queryItems = nil
            request.url = components?.url
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LastFMError.httpError(statusCode: -1, message: "No HTTP response")
        }
        
        // Check for HTTP errors first
        if !(200...299).contains(httpResponse.statusCode) {
            // Try to parse last.fm error from response body
            let errorMessage = parseErrorFromResponse(data) ?? "Unknown error (HTTP \(httpResponse.statusCode))"
            throw LastFMError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // Check if response contains last.fm error (some API errors return HTTP 200 with error body)
        if let errorResponse = try? JSONDecoder().decode(LastFMWrappedErrorResponse.self, from: data) {
            throw LastFMError.apiError("Error \(errorResponse.error.error): \(errorResponse.error.message)")
        }
        if let errorResponse = try? JSONDecoder().decode(LastFMErrorResponse.self, from: data) {
            throw LastFMError.apiError("Error \(errorResponse.error): \(errorResponse.message)")
        }
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw LastFMError.decodingError(error)
        }
    }
    
    private func parseErrorFromResponse(_ data: Data) -> String? {
        // Try wrapped format first
        if let wrapped = try? JSONDecoder().decode(LastFMWrappedErrorResponse.self, from: data) {
            return "Error \(wrapped.error.error): \(wrapped.error.message)"
        }
        // Try direct format
        if let direct = try? JSONDecoder().decode(LastFMErrorResponse.self, from: data) {
            return "Error \(direct.error): \(direct.message)"
        }
        // Try raw string
        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return raw
        }
        return nil
    }
    
    /// Computes the last.fm API signature (MD5 of sorted key=value pairs concatenated with the secret).
    /// Note: `format` and `api_sig` parameters are excluded from the signature per last.fm spec.
    private func apiSignature(params: [String: String]) -> String {
        let sortedKeys = params.keys.sorted { $0 < $1 }
        let filteredKeys = sortedKeys.filter { $0 != "api_sig" && $0 != "format" }
        let stringToSign = filteredKeys.map { "\($0)\(params[$0]!)" }.joined() + apiSecret
        return stringToSign.md5
    }
}

// MARK: - Helpers

private struct EmptyResponse: Decodable {}

/// Pure-Swift MD5 implementation (no CommonCrypto dependency needed).
extension String {
    var md5: String {
        let message = Data(self.utf8)
        let hash = MD5.hash(data: message)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

/// MD5 hash computation in pure Swift.
enum MD5 {
    private static let shift: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    ]
    
    private static let table: [UInt32] = (0..<64).map { i in
        UInt32(pow(2, 32) * abs(sin(Double(i + 1))))
    }
    
    static func hash(data: Data) -> [UInt8] {
        var message = data.bytes
        
        // Step 1: Append padding bits
        let originalBitCount = message.count * 8
        message.append(0x80)
        while (message.count * 8 + 64) % 512 != 0 {
            message.append(0x00)
        }
        
        // Step 2: Append length (64-bit little-endian)
        let bitCountLE = originalBitCount.littleEndian
        withUnsafeBytes(of: bitCountLE) { message.append(contentsOf: $0) }
        
        // Step 3: Initialize MD buffer
        var a: UInt32 = 0x67452301
        var b: UInt32 = 0xEFCDAB89
        var c: UInt32 = 0x98BADCFE
        var d: UInt32 = 0x10325476
        
        // Step 4: Process 512-bit blocks
        for blockOffset in stride(from: 0, to: message.count, by: 64) {
            var M = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let offset = blockOffset + i * 4
                M[i] = UInt32(message[offset])
                    | UInt32(message[offset + 1]) << 8
                    | UInt32(message[offset + 2]) << 16
                    | UInt32(message[offset + 3]) << 24
            }
            
            var A = a, B = b, C = c, D = d
            
            for i in 0..<64 {
                var f: UInt32
                var g: Int
                
                if i < 16 {
                    f = (B & C) | ((~B) & D)
                    g = i
                } else if i < 32 {
                    f = (B & D) | (C & (~D))
                    g = (5 * i + 1) % 16
                } else if i < 48 {
                    f = B ^ C ^ D
                    g = (3 * i + 5) % 16
                } else {
                    f = C ^ (B | (~D))
                    g = (7 * i) % 16
                }
                
                let temp = A &+ f &+ table[i] &+ M[g]
                A = D
                D = C
                C = B
                B = B &+ rotateLeft(temp, shift[i])
            }
            
            a &+= A
            b &+= B
            c &+= C
            d &+= D
        }
        
        // Step 5: Output (little-endian)
        var result = [UInt8](repeating: 0, count: 16)
        let v: [UInt32] = [a, b, c, d]
        for i in 0..<4 {
            let le = v[i].littleEndian
            withUnsafeBytes(of: le) { result.replaceSubrange(i * 4..<i * 4 + 4, with: Array($0)) }
        }
        return result
    }
    
    private static func rotateLeft(_ value: UInt32, _ bits: UInt32) -> UInt32 {
        return (value << bits) | (value >> (32 - bits))
    }
}

private extension Data {
    var bytes: [UInt8] {
        return [UInt8](self)
    }
}
