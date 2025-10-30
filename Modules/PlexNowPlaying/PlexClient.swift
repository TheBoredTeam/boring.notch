//
//  PlexClient.swift
//  BoringNotch (Plex Module)
//
//  Cliente simple para consultar `/:/sessions` del PMS y
//  actualizar el ViewModel con la pista en reproducción.
//  Incluye logs detallados con timestamp.
//

import Foundation

public final class PlexClient: NSObject {
    public let baseURL: URL
    public let token: String
    private var pollTimer: Timer?

    /// Activa/imprime logs detallados a la consola de Xcode.
    private let debugLogging: Bool

    public init(baseURL: URL, token: String, debugLogging: Bool = false) {
        self.baseURL = baseURL
        self.token = token
        self.debugLogging = debugLogging
        super.init()
    }

    deinit { stopPolling() }

    public func startPolling(interval: TimeInterval = 5.0) {
        stopPolling()
        DispatchQueue.main.async {
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { await self?.pollOnce() }
            }
        }
        Task { await pollOnce() }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Lectura de sesiones

    public func pollOnce() async {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return }
        comps.path = "/status/sessions"
        comps.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        guard let url = comps.url else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/xml", forHTTPHeaderField: "Accept")

        if debugLogging {
            print("🛰️ [PlexClient] GET \(baseURL.host ?? ""):/status/sessions  token=\(mask(token))")
        }

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

            if let track = PlexNowPlayingXML.parseFirstPlayingTrack(from: data) {
                if debugLogging {
                    print("🎵 [PlexClient] Track detectado: artist=\(track.artist)  album=\(track.album)  title=\(track.title)")
                }
                await PlexNowPlayingViewModel.shared.setNowPlaying(
                    NowPlaying(artist: track.artist, album: track.album, albumMBIDs: [])
                )
            } else if debugLogging {
                print("⚠️ [PlexClient] No se detectó <Player state=\"playing\"> en /status/sessions")
            }

        } catch {
            if debugLogging {
                print("❌ [PlexClient] Error en request /status/sessions: \(error)")
            }
        }
    }

    // MARK: - Modelo mínimo + XML parsing

    private struct PlayingTrack { let title: String; let artist: String; let album: String }

    private enum PlexNowPlayingXML {
        static func parseFirstPlayingTrack(from data: Data) -> PlayingTrack? {
            let delegate = SessionsParserDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            _ = parser.parse()
            return delegate.firstPlayingTrack
        }

        private final class SessionsParserDelegate: NSObject, XMLParserDelegate {
            var firstPlayingTrack: PlayingTrack?
            private var insideTrack = false
            private var currentTrack: (title: String?, artist: String?, album: String?) = (nil, nil, nil)
            private var currentTrackHasPlayingPlayer = false

            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String : String] = [:]) {
                if firstPlayingTrack != nil { return }
                if name == "Track" {
                    insideTrack = true
                    currentTrackHasPlayingPlayer = false
                    currentTrack.title  = attributes["title"]
                    currentTrack.artist = attributes["grandparentTitle"] ?? attributes["artist"]
                    currentTrack.album  = attributes["parentTitle"] ?? attributes["album"]
                } else if insideTrack && name == "Player" {
                    if let state = attributes["state"], state.lowercased() == "playing" {
                        currentTrackHasPlayingPlayer = true
                    }
                }
            }

            func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
                if firstPlayingTrack != nil { return }
                if name == "Track" && insideTrack {
                    defer {
                        insideTrack = false
                        currentTrack = (nil, nil, nil)
                        currentTrackHasPlayingPlayer = false
                    }
                    guard currentTrackHasPlayingPlayer,
                          let artist = currentTrack.artist, !artist.isEmpty,
                          let album  = currentTrack.album,  !album.isEmpty,
                          let title  = currentTrack.title,  !title.isEmpty else { return }
                    firstPlayingTrack = PlayingTrack(title: title, artist: artist, album: album)
                }
            }
        }
    }

    // Enmascara el token para logs
    private func mask(_ t: String) -> String {
        guard t.count > 6 else { return "•••" }
        let head = t.prefix(3)
        let tail = t.suffix(3)
        return "\(head)••••••\(tail)"
    }
}
