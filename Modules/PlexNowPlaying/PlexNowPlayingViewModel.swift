//
//  PlexNowPlayingViewModel.swift
//  BoringNotch (Plex Module)
//

import Foundation
import Combine

/// Modelo mínimo para representar lo que está sonando.
public struct NowPlaying: Sendable {
    public let artist: String
    public let album: String
    public let albumMBIDs: [String]?
    public init(artist: String, album: String, albumMBIDs: [String]? = nil) {
        self.artist = artist
        self.album = album
        self.albumMBIDs = albumMBIDs
    }
}

public final class PlexNowPlayingViewModel: ObservableObject {

    /// Singleton para poder invocarlo desde `PlexClient`.
    public static let shared = PlexNowPlayingViewModel()

    // Estado que consume la UI
    public enum State {
        case idle
        case loading
        case error(String)
        case ready(NowPlaying, AlbumFacts)
    }

    @Published public private(set) var state: State = .idle

    // Cliente del enricher (se inicializa leyendo la URL guardada en UserDefaults)
    private var factsClient: FactsClient

    // Último NP detectado
    private var currentNowPlaying: NowPlaying?

    // Identidad simple de la pista para onChange
    public var trackIdentity: String? {
        guard let np = currentNowPlaying else { return nil }
        return "\(np.artist)|\(np.album)"
    }

    /// Inicializa con FactsClient apuntando a ENRICHER_URL (o `http://127.0.0.1:5173` por defecto)
    public init() {
        let base = URL(string: UserDefaults.standard.string(forKey: "ENRICHER_URL") ?? "http://127.0.0.1:5173")!
        self.factsClient = FactsClient(apiBase: base, debugLogging: true)
        print("🔧 [VM] FactsClient base=\(base.absoluteString)")
    }

    // MARK: - Flujo principal

    /// Setea el “Now Playing” actual y dispara un refresh
    @MainActor
    public func setNowPlaying(_ np: NowPlaying) async {
        currentNowPlaying = np
        let mbidsCount = np.albumMBIDs?.count ?? 0
        print("🎯 [VM] setNowPlaying artist='\(np.artist)' album='\(np.album)' mbids=\(mbidsCount)")
        await refresh()
    }

    /// Fuerza un refresh usando el `currentNowPlaying`
    @MainActor
    public func refresh() async {
        guard let np = currentNowPlaying else { return }
        state = .loading
        print("🧠 [VM] enrich → artist='\(np.artist)' album='\(np.album)'")

        do {
            let facts = try await factsClient.enrich(
                artist: np.artist,
                album: np.album,
                albumMBIDs: np.albumMBIDs ?? []
            )
            print("✅ [VM] enrich OK  label=\(facts.label ?? "-")  date=\(facts.releaseDate ?? "-")  sources=\(facts.sources.count)")
            state = .ready(np, facts)
        } catch {
            print("❌ [VM] enrich error: \(error)")
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Polling de Plex

    // Guarda referencia fuerte; si no, el Timer interno se invalida.
    private var plexClient: PlexClient?

    @MainActor
    public func startPlexPolling(baseURL: URL, token: String) {
        plexClient?.stopPolling()
        plexClient = PlexClient(baseURL: baseURL, token: token, debugLogging: true)
        plexClient?.startPolling(interval: 5)
        print("▶️ [VM] startPlexPolling base=\(baseURL.absoluteString)")
    }

    @MainActor
    public func stopPlexPolling() {
        plexClient?.stopPolling()
        plexClient = nil
        print("⏹ [VM] stopPlexPolling")
    }

    deinit {
        plexClient?.stopPolling()
    }
}
