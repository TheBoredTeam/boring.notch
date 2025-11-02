//
//  PlexNowPlayingContainerView.swift
//  boringNotch (Plex Module)
//  Arranca el poller de Plex aunque no se abra ConfigView.
//

import SwiftUI
import Defaults

public struct PlexNowPlayingContainerView: View {
    @Default(.pmsURL)    private var pmsURL
    @Default(.plexToken) private var plexToken

    public init() {}

    public var body: some View {
        // ⬇️ Tu vista actual de “now playing” (no la toques)
        PlexNowPlayingView()
            // Auto-arranque al montar la UI principal
            .onAppear { startOrRestartPlex() }
            // Si cambian credenciales en Defaults, reiniciamos el poller
            .onChange(of: pmsURL)    { _ in startOrRestartPlex() }
            .onChange(of: plexToken) { _ in startOrRestartPlex() }
    }

    private func startOrRestartPlex() {
        let urlString = pmsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token     = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString), !token.isEmpty else { return }
        PlexNowPlayingViewModel.shared.startPlexPolling(baseURL: url, token: token)
    }
}
