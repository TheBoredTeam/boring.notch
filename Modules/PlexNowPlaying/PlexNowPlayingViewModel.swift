//
//  PlexNowPlayingViewModel.swift
//  BoringNotch (Plex Module)
//

import Foundation
import Combine

/// Modelo mínimo para representar lo que está sonando.
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

/// Estado del panel de facts.
public enum FactsState: Sendable {
    case idle
    case loading(NowPlaying)
    case loaded(NowPlaying, AlbumFacts)
    case error(String)
}

/// ViewModel centralizado (singleton) para el módulo.
@MainActor
public final class PlexNowPlayingViewModel: ObservableObject {

    public static let shared = PlexNowPlayingViewModel()

    // Entrada / salida
    @Published public private(set) var state: FactsState = .idle
    @Published public private(set) var current: NowPlaying?

    // Clientes
    private var factsClient: FactsClient
    private var plexClient: PlexClient?

    // Logs
    private let debugLogging: Bool = true

    private init() {
        // Lee URLs de UserDefaults (si no existen, usa localhost)
        let enricherStr = UserDefaults.standard.string(forKey: "ENRICHER_URL") ?? "http://127.0.0.1:5173"
        let enricherURL = URL(string: enricherStr) ?? URL(string: "http://127.0.0.1:5173")!
        self.factsClient = FactsClient(apiBase: enricherURL, debugLogging: debugLogging)
    }

    // MARK: - Config dinámico

    /// Actualiza la base del Enricher en caliente.
    public func updateEnricher(baseURL: URL) {
        self.factsClient = FactsClient(apiBase: baseURL, debugLogging: debugLogging)
        if debugLogging { print("🔧 [VM] FactsClient base=\(baseURL.absoluteString)") }
    }

    // MARK: - Mutaciones de reproducción

    /// Se llama cuando PlexClient detecta una nueva pista.
    public func setNowPlaying(_ np: NowPlaying) async {
        if let cur = current, cur == np {
            if debugLogging { print("🧷 [VM] setNowPlaying ignorado (sin cambios)") }
            return
        }
        current = np
        state = .loading(np)
        await refresh()
    }

    /// Forzar re-enriquecido para la pista actual (p. ej., al reanudar).
    public func refresh() async {
        guard let np = current else {
            state = .idle
            return
        }
        do {
            let facts = try await factsClient.enrich(
                artist: np.artist,
                album: np.album,
                albumMBIDs: np.albumMBIDs ?? []
            )
            state = .loaded(np, facts)
            if debugLogging {
                print("✅ [VM] Facts loaded for \(np.artist) — \(np.album)")
            }
        } catch {
            state = .error(error.localizedDescription)
            if debugLogging {
                print("❌ [VM] refresh error: \(error)")
            }
        }
    }

    public func clearNowPlaying() {
        current = nil
        state = .idle
    }

    // MARK: - Control del PlexClient

    public func startPlexPolling(baseURL: URL, token: String) {
        plexClient?.stopPolling()
        let client = PlexClient(baseURL: baseURL, token: token, debugLogging: debugLogging)
        self.plexClient = client
        client.startPolling() // autoajusta el intervalo según estado
        if debugLogging { print("▶️ [VM] startPlexPolling base=\(baseURL.absoluteString)") }
    }

    public func stopPlexPolling() {
        plexClient?.stopPolling()
        plexClient = nil
        if debugLogging { print("⏹ [VM] stopPlexPolling") }
    }

    deinit {
        plexClient?.stopPolling()
    }
}
