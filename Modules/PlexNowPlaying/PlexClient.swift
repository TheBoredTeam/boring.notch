//
//  PlexClient.swift
//  BoringNotch (Plex Module)
//
//  Consulta `/:/status/sessions` del PMS y actualiza el VM.
//  - Polling autoajustable por estado (playing/paused/idle)
//  - Solo refresca en cambio de canción o al reanudar playback
//  - Extrae MBIDs desde GUIDs de Plex
//

import Foundation

public final class PlexClient: NSObject {
    public let baseURL: URL
    public let token: String

    private var pollTimer: Timer?
    private let debugLogging: Bool

    // Estado previo para detectar cambios/resume
    private var lastSignature: String?
    private var lastIsPlaying: Bool?

    // Intervalos de polling por estado
    private struct Intervals {
        static let playing: TimeInterval = 3.0   // rápido
        static let paused:  TimeInterval = 6.0   // medio
        static let idle:    TimeInterval = 12.0  // lento
    }
    private var currentInterval: TimeInterval = Intervals.idle

    public init(baseURL: URL, token: String, debugLogging: Bool = false) {
        self.baseURL = baseURL
        self.token = token
        self.debugLogging = debugLogging
        super.init()
    }

    deinit { stopPolling() }

    // MARK: - Control de polling

    public func startPolling() {
        scheduleTimer(interval: currentInterval)
        Task { await pollOnce() } // primer tick inmediato
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        lastSignature = nil
        lastIsPlaying = nil
    }

    private func scheduleTimer(interval: TimeInterval) {
        pollTimer?.invalidate()
        currentInterval = interval
        DispatchQueue.main.async {
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { await self?.pollOnce() }
            }
            self.pollTimer?.tolerance = interval * 0.2
            if let t = self.pollTimer {
                RunLoop.main.add(t, forMode: .common)
            }
            if self.debugLogging {
                print("⏱️ [PlexClient] Timer interval=\(String(format: "%.1f", interval))s")
            }
        }
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
            guard code == 200 else {
                if debugLogging { print("❌ [PlexClient] HTTP \(code)") }
                return
            }

            let snap = PlexNowPlayingXML.parseSnapshot(from: data)

            // Ajusta frecuencia por estado actual
            let desiredInterval: TimeInterval
            if let s = snap {
                desiredInterval = s.isPlaying ? Intervals.playing : Intervals.paused
            } else {
                desiredInterval = Intervals.idle
            }
            if abs(desiredInterval - currentInterval) > 0.1 {
                scheduleTimer(interval: desiredInterval)
            }

            // Sin sesión → no toques el VM
            guard let s = snap else {
                if debugLogging { print("ℹ️ [PlexClient] Sin sesión activa.") }
                lastSignature = nil
                lastIsPlaying = nil
                return
            }

            // Firma única de la pista
            let signature = "\(s.artist)|\(s.album)|\(s.title)"

            let isChangeOfTrack = (lastSignature == nil) || (signature != lastSignature)
            let resumedPlayback  = (lastIsPlaying == false && s.isPlaying == true)

            if debugLogging {
                print("🎵 [PlexClient] \(s.isPlaying ? "▶️ playing" : "⏸️ paused")  \(s.artist) — \(s.album) — \(s.title)")
                print("🧩 MBIDs=\(s.albumMBIDs)")
                print("🔎 changeOfTrack=\(isChangeOfTrack)  resumed=\(resumedPlayback)")
            }

            if isChangeOfTrack {
                await PlexNowPlayingViewModel.shared.setNowPlaying(
                    NowPlaying(artist: s.artist, album: s.album, albumMBIDs: s.albumMBIDs)
                )
            } else if resumedPlayback {
                await PlexNowPlayingViewModel.shared.refresh()
            }

            lastSignature = signature
            lastIsPlaying = s.isPlaying

        } catch {
            if debugLogging {
                print("❌ [PlexClient] Error request /status/sessions: \(error)")
            }
        }
    }

    // MARK: - Snapshot + XML parsing

    private struct PlayingSnapshot {
        let title: String
        let artist: String
        let album: String
        let albumMBIDs: [String]
        let isPlaying: Bool
    }

    private enum PlexNowPlayingXML {
        static func parseSnapshot(from data: Data) -> PlayingSnapshot? {
            let delegate = SessionsParserDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            _ = parser.parse()
            return delegate.snapshot
        }

        /// Parser: primera pista con Player state playing/paused.
        /// Extrae título/álbum/artista, estado `isPlaying` y MBIDs desde GUIDs.
        private final class SessionsParserDelegate: NSObject, XMLParserDelegate {
            var snapshot: PlayingSnapshot?

            private var insideTrack = false
            private var currentHasPlayer = false
            private var currentIsPlaying = false

            private var currentTitle = ""
            private var currentArtist = ""
            private var currentAlbum = ""
            private var currentGUIDs: [String] = []

            func parser(_ parser: XMLParser,
                        didStartElement name: String,
                        namespaceURI: String?,
                        qualifiedName qName: String?,
                        attributes: [String : String] = [:]) {

                if snapshot != nil { return }

                switch name {
                case "Track":
                    insideTrack = true
                    currentHasPlayer = false
                    currentIsPlaying = false
                    currentGUIDs.removeAll()

                    // Para música: grandparentTitle=artist, parentTitle=album
                    currentTitle  = attributes["title"] ?? ""
                    currentArtist = attributes["grandparentTitle"] ?? attributes["artist"] ?? ""
                    currentAlbum  = attributes["parentTitle"] ?? attributes["album"] ?? ""

                    if let g = attributes["guid"], !g.isEmpty {
                        currentGUIDs.append(g)
                    }

                case "Guid":
                    if insideTrack, let id = attributes["id"], !id.isEmpty {
                        currentGUIDs.append(id)
                    }

                case "Player":
                    if insideTrack {
                        currentHasPlayer = true
                        if let st = attributes["state"]?.lowercased() {
                            currentIsPlaying = (st == "playing")
                            // Si quieres forzar Plexamp: filtra por attributes["product"] == "Plexamp"
                        }
                    }

                default:
                    break
                }
            }

            func parser(_ parser: XMLParser,
                        didEndElement name: String,
                        namespaceURI: String?,
                        qualifiedName qName: String?) {

                if snapshot != nil { return }

                if name == "Track" && insideTrack {
                    defer {
                        insideTrack = false
                        currentHasPlayer = false
                        currentIsPlaying = false
                        currentTitle = ""; currentArtist = ""; currentAlbum = ""
                        currentGUIDs.removeAll()
                    }

                    guard currentHasPlayer,
                          !currentArtist.isEmpty,
                          !currentAlbum.isEmpty,
                          !currentTitle.isEmpty else { return }

                    let mbids = extractAlbumMBIDs(from: currentGUIDs)

                    snapshot = PlayingSnapshot(
                        title: currentTitle,
                        artist: currentArtist,
                        album: currentAlbum,
                        albumMBIDs: mbids,
                        isPlaying: currentIsPlaying
                    )
                }
            }

            // --- MBID helpers ---

            private func extractAlbumMBIDs(from guids: [String]) -> [String] {
                let uuidRegex = try! NSRegularExpression(
                    pattern: #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#,
                    options: []
                )

                struct Found: Hashable {
                    let raw: String
                    let uuid: String
                    let weight: Int
                }

                var set = Set<Found>()

                for g in guids {
                    let lower = g.lowercased()
                    guard lower.contains("mbid") || lower.contains("musicbrainz") else { continue }

                    if let m = uuidRegex.firstMatch(in: g, options: [], range: NSRange(g.startIndex..., in: g)),
                       let r = Range(m.range, in: g) {
                        let uuid = String(g[r]).lowercased()
                        let w: Int
                        if lower.contains("release-group") || lower.contains("release_group") {
                            w = 0
                        } else if lower.contains("/album/") || lower.contains("/release/") {
                            w = 1
                        } else if lower.contains("/recording/") || lower.contains("/track/") {
                            w = 2
                        } else {
                            w = 3
                        }
                        set.insert(Found(raw: g, uuid: uuid, weight: w))
                    }
                }

                let sorted = set.sorted { a, b in
                    if a.weight != b.weight { return a.weight < b.weight }
                    return a.uuid < b.uuid
                }

                var seen = Set<String>()
                var result: [String] = []
                for f in sorted where !seen.contains(f.uuid) {
                    seen.insert(f.uuid)
                    result.append(f.uuid)
                }
                return result
            }
        }
    }

    // MARK: - Util

    private func mask(_ t: String) -> String {
        guard t.count > 6 else { return "•••" }
        let head = t.prefix(3)
        let tail = t.suffix(3)
        return "\(head)••••••\(tail)"
    }
}
