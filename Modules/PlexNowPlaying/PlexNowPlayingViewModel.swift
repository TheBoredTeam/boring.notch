//
//  PlexNowPlayingViewModel.swift
//  boringNotch (Plex Module)
//

import Foundation
import Defaults
import Combine   // <- Necesario para Defaults.publisher y AnyCancellable

public enum FactsState: Sendable, Equatable {
    case idle
    case loading
    case ready(AlbumFacts)
    case error(String)
}

@MainActor
public final class PlexNowPlayingViewModel: ObservableObject {

    public static let shared = PlexNowPlayingViewModel()

    // Salidas
    @Published public private(set) var state: FactsState = .idle
    @Published public private(set) var snapshotNowPlaying: NowPlaying?

    // Plex
    private var plex: PlexClient?
    private var isPollingActive = false

    // Bootstrap
    private var bootstrapTask: Task<Void, Never>?
    private var lastBootstrapCredentials: (String, String)?

    // Facts
    private var isPaused: Bool = true
    private var lastAlbumKey: String?
    private var factsCache: [String: AlbumFacts] = [:]
    private var retriedForAlbum: Set<String> = []

    // Combine
    private var cancellables: Set<AnyCancellable> = []

    // Init
    private init() {
        // Arranca bootstrap al iniciar y cuando cambien las credenciales
        Defaults.publisher(.pmsURL)
            .merge(with: Defaults.publisher(.plexToken))
            .sink { [weak self] _ in
                Task { @MainActor in self?.startBootstrapLoopIfNeeded() }
            }
            .store(in: &cancellables)

        startBootstrapLoopIfNeeded()
    }

    // MARK: - Bootstrap automático (sin UI)

    private func startBootstrapLoopIfNeeded() {
        guard !isPollingActive else { return }

        let urlStr = Defaults[.pmsURL].trimmingCharacters(in: .whitespacesAndNewlines)
        let tok    = Defaults[.plexToken].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlStr.isEmpty, !tok.isEmpty else {
            stopBootstrapLoop()
            return
        }

        // Evita reiniciar la misma tarea si las credenciales no cambiaron
        let creds = (urlStr, tok)
        if let last = lastBootstrapCredentials, last == creds, bootstrapTask != nil { return }
        lastBootstrapCredentials = creds

        stopBootstrapLoop() // cancela si existía
        print("🧭 [VM] Bootstrap: armado. Esperando playback…")

        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && !self.isPollingActive {
                self.configureClientIfNeeded(urlStr: urlStr, token: tok)
                await self.plex?.pollOnce() // toque ligero; si hay playback recibiremos NowPlaying
                try? await Task.sleep(nanoseconds: 7_000_000_000) // 7s
            }
        }
    }

    private func stopBootstrapLoop() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
    }

    private func configureClientIfNeeded(urlStr: String, token: String) {
        if plex != nil { return }
        guard let url = URL(string: urlStr) else { return }

        let client = PlexClient(baseURL: url, token: token, debugLogging: true)
        client.onNowPlayingChange = { [weak self] np, paused in
            Task { @MainActor in self?.handleNowPlayingUpdate(now: np, paused: paused) }
        }
        plex = client
        print("🧭 [VM] PlexClient configurado (bootstrap)")
    }

    // MARK: - API pública

    /// Botón “Probar conexión / Reiniciar poller”
    public func startPlexPolling(baseURL: URL, token: String) {
        stopBootstrapLoop()
        let client = PlexClient(baseURL: baseURL, token: token, debugLogging: true)
        client.onNowPlayingChange = { [weak self] np, paused in
            Task { @MainActor in self?.handleNowPlayingUpdate(now: np, paused: paused) }
        }
        plex = client
        client.stopPolling()
        client.startPolling(interval: 5.0)
        isPollingActive = true
        print("🧭 [VM] Poller arrancado explícitamente")
    }

    public func forceRefresh() async {
        guard let np = snapshotNowPlaying else {
            await plex?.pollOnce()
            return
        }
        await fetchFactsIfNeeded(for: np, reason: .forced)
    }

    // MARK: - Manejo de NowPlaying

    private enum RefreshReason { case firstSeen, trackChange, resumePlay, forced }

    private func handleNowPlayingUpdate(now: NowPlaying?, paused: Bool) {
        snapshotNowPlaying = now
        isPaused = paused

        guard let np = now else { return }

        // Primer NowPlaying → inicia loop y apaga bootstrap
        if !isPollingActive {
            plex?.startPolling(interval: 5.0)
            isPollingActive = true
            stopBootstrapLoop()
            print("▶️ [VM] NowPlaying detectado → iniciando loop de polling")
        }

        let albumKey = "\(np.artist)|\(np.album)"
        let firstTime = (lastAlbumKey == nil)
        let albumChanged = (albumKey != lastAlbumKey)
        let resumed = (state == .loading && !paused)

        lastAlbumKey = albumKey

        if firstTime {
            Task { await fetchFactsIfNeeded(for: np, reason: .firstSeen) }
            return
        }
        if albumChanged {
            Task { await fetchFactsIfNeeded(for: np, reason: .trackChange) }
            return
        }
        if resumed {
            Task { await fetchFactsIfNeeded(for: np, reason: .resumePlay) }
            return
        }

        if case .loading = state, !retriedForAlbum.contains(albumKey) {
            retriedForAlbum.insert(albumKey)
            Task { await fetchFactsIfNeeded(for: np, reason: .trackChange) }
        }
    }

    // MARK: - Facts

    private func fetchFactsIfNeeded(for now: NowPlaying, reason: RefreshReason) async {
        if isPaused && reason != .forced { return }

        let albumKey = "\(now.artist)|\(now.album)"

        if let cached = factsCache[albumKey] {
            state = .ready(cached)
            if reason != .forced { return }
        } else {
            state = .loading
        }

        if let facts = await FactsClient.shared.fetchFacts(artist: now.artist, album: now.album) {
            factsCache[albumKey] = facts
            retriedForAlbum.remove(albumKey)
            state = .ready(facts)
        } else {
            state = factsCache[albumKey].map { .ready($0) } ?? .error("No se pudo obtener información")
        }
    }
}
