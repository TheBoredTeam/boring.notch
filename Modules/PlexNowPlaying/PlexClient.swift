//
//  PlexClient.swift
//  boringNotch (Plex Module)
//

import Foundation

// Snapshot mínimo de lo que está sonando
public struct NowPlaying: Sendable, Equatable {
    public let artist: String
    public let album: String
    public let albumMBIDs: [String]?
    public init(artist: String, album: String, albumMBIDs: [String]? = nil) {
        self.artist = artist
        self.album = album
        self.albumMBIDs = albumMBIDs
    }
}

public final class PlexClient: NSObject {
    public let baseURL: URL
    public let token: String
    private var pollTimer: Timer?

    /// Cuando cambia la canción o cambia pausa⟷play.
    /// (artist, album, isPaused)
    public var onNowPlayingChange: ((NowPlaying?, Bool) -> Void)?

    /// Activa logs detallados
    public var debugLogging: Bool = true

    public init(baseURL: URL, token: String, debugLogging: Bool = true) {
        self.baseURL = baseURL
        self.token = token
        self.debugLogging = debugLogging
        super.init()
    }

    deinit { stopPolling() }

    // MARK: - Poll

    public func startPolling(interval: TimeInterval = 5.0) {
        stopPolling()
        if debugLogging { print("🛰️ [PlexClient] startPolling interval=\(interval)s  host=\(baseURL.host ?? "?")") }
        DispatchQueue.main.async {
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { await self?.pollOnce() }
            }
        }
        Task { await pollOnce() }
    }

    public func stopPolling() {
        if debugLogging { print("🛰️ [PlexClient] stopPolling()") }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Un tick “manual” (útil desde forceRefresh del VM).
    public func pollOnce() async {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return }
        comps.path = "/status/sessions"
        comps.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        guard let url = comps.url else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/xml", forHTTPHeaderField: "Accept")

        if debugLogging { print("🛰️ [PlexClient] GET \(url.absoluteString)") }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1

            if debugLogging {
                print("🛰️ [PlexClient] ← status=\(code) bytes=\(data.count)")
                if data.count > 0 {
                    let preview = String(data: data.prefix(600), encoding: .utf8) ?? "<bin>"
                    print("🛰️ [PlexClient] XML preview:\n\(preview)\n——")
                }
            }

            guard code == 200 else { return }

            let parsed = PlexNowPlayingXML.parseFirstPlayingTrack(from: data)
            let isPaused = PlexNowPlayingXML.detectPaused(from: data)

            if let t = parsed {
                let np = NowPlaying(artist: t.artist, album: t.album, albumMBIDs: t.mbids)
                if debugLogging {
                    print("🎵 [PlexClient] nowPlaying=\(np.artist) — \(np.album)  paused=\(isPaused)")
                }
                onNowPlayingChange?(np, isPaused)
            } else {
                if debugLogging { print("⚠️ [PlexClient] No playing track") }
                onNowPlayingChange?(nil, true)
            }

        } catch {
            if debugLogging { print("❌ [PlexClient] /status/sessions error: \(error)") }
        }
    }

    // MARK: - XML parsing

    private struct PlayingTrack { let title: String; let artist: String; let album: String; let mbids: [String]? }

    private enum PlexNowPlayingXML {
        static func parseFirstPlayingTrack(from data: Data) -> PlayingTrack? {
            let delegate = SessionsParserDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            _ = parser.parse()
            return delegate.firstPlayingTrack
        }
        static func detectPaused(from data: Data) -> Bool {
            let d = SessionsParserDelegate()
            let p = XMLParser(data: data)
            p.delegate = d
            _ = p.parse()
            return d.currentTrackIsPaused
        }

        private final class SessionsParserDelegate: NSObject, XMLParserDelegate {
            var firstPlayingTrack: PlayingTrack?
            var currentTrackIsPaused = true

            private var insideTrack = false
            private var currentTrack: (title: String?, artist: String?, album: String?, mbids: [String]?) = (nil, nil, nil, nil)
            private var currentTrackHasPlayingPlayer = false

            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String : String] = [:]) {
                if firstPlayingTrack != nil { return }
                if name == "Track" {
                    insideTrack = true
                    currentTrackHasPlayingPlayer = false
                    currentTrack.title  = attributes["title"]
                    currentTrack.artist = attributes["grandparentTitle"] ?? attributes["artist"]
                    currentTrack.album  = attributes["parentTitle"] ?? attributes["album"]
                    // Si Plex expone GUIDs con MBIDs en atributos/guid (puede no estar):
                    if let guid = attributes["guid"], guid.contains("musicbrainz") {
                        // ejemplo: "com.plexapp.agents.music:mbid://album/xxxxx?lang=en"
                        let comps = guid.split(separator: "/").map(String.init)
                        let last = comps.last ?? ""
                        currentTrack.mbids = [last]
                    }
                } else if insideTrack && name == "Player" {
                    if let state = attributes["state"] {
                        if state.lowercased() == "playing" { currentTrackHasPlayingPlayer = true; currentTrackIsPaused = false }
                        if state.lowercased() == "paused"  { currentTrackIsPaused = true }
                    }
                }
            }

            func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
                if firstPlayingTrack != nil { return }
                if name == "Track" && insideTrack {
                    defer {
                        insideTrack = false
                        currentTrack = (nil, nil, nil, nil)
                        currentTrackHasPlayingPlayer = false
                    }
                    guard currentTrackHasPlayingPlayer,
                          let artist = currentTrack.artist, !artist.isEmpty,
                          let album  = currentTrack.album,  !album.isEmpty,
                          let title  = currentTrack.title,  !title.isEmpty else { return }
                    firstPlayingTrack = PlayingTrack(title: title, artist: artist, album: album, mbids: currentTrack.mbids)
                }
            }
        }
    }
}
