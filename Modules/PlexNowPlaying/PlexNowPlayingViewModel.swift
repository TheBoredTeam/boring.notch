//
//  PlexNowPlayingViewModel.swift
//  boringNotch (Plex Module)
//

import Foundation
import Defaults

public enum FactsState: Sendable, Equatable {
    case idle
    case loading
    case ready(AlbumFacts)
    case error(String)
}

@MainActor
public final class PlexNowPlayingViewModel: ObservableObject {
    public static let shared = PlexNowPlayingViewModel()

    @Published public private(set) var state: FactsState = .idle

    private(set) var snapshotNowPlaying: NowPlaying?
    private(set) var isPaused: Bool = true

    private var plex: PlexClient?
    private var pollConfigured = false

    public func startPlexPolling(baseURL: URL, token: String) {
        if pollConfigured, let p = plex, p.baseURL == baseURL && p.token == token {
            if p.debugLogging { print("🧭 [VM] startPlexPolling: ya configurado") }
            return
        }
        let client = PlexClient(baseURL: baseURL, token: token, debugLogging: true)
        client.onNowPlayingChange = { [weak self] np, paused in
            Task { @MainActor in
                guard let self else { return }
                self.snapshotNowPlaying = np
                self.isPaused = paused
                if let np {
                    print("🧭 [VM] NowPlaying → \(np.artist) — \(np.album) paused=\(paused)")
                    await self.refreshFactsIfNeeded(now: np)
                } else {
                    print("🧭 [VM] NowPlaying vacío (paused=\(paused))")
                }
            }
        }
        plex = client
        pollConfigured = true
        client.startPolling(interval: 5.0)
        print("🧭 [VM] Poller configurado (Plex)")
    }

    public func forceRefresh() async {
        guard let np = snapshotNowPlaying else {
            print("🧭 [VM] forceRefresh: no hay NowPlaying aún. pollOnce()…")
            await plex?.pollOnce()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let retry = snapshotNowPlaying {
                await refreshFactsIfNeeded(now: retry, force: true)
            } else {
                print("🧭 [VM] forceRefresh: sigue sin NowPlaying.")
            }
            return
        }
        await refreshFactsIfNeeded(now: np, force: true)
    }

    private func refreshFactsIfNeeded(now: NowPlaying, force: Bool = false) async {
        guard !isPaused else {
            print("🧭 [VM] refreshFactsIfNeeded: en pausa → skip")
            return
        }
        state = .loading
        let artist = now.artist
        let album  = now.album

        print("🔁 [VM] pidiendo facts para: \(artist) — \(album)")
        if let facts = await FactsClient.shared.fetchFacts(artist: artist, album: album) {
            state = .ready(facts)
            print("✅ [VM] facts OK (label=\(facts.label ?? "-"), released=\(facts.releaseDate ?? "-"))")
        } else {
            state = .error("No se pudo obtener información")
            print("❌ [VM] facts fallo")
        }
    }
}
