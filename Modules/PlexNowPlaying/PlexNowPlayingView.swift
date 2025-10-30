//
//  PlexNowPlayingView.swift
//  BoringNotch (Plex Module)
//

import SwiftUI

public struct PlexNowPlayingView: View {

    @ObservedObject private var vm = PlexNowPlayingViewModel.shared

    public init() {}

    public var body: some View {
        // Grid 2 columnas: izquierda Now Playing, derecha Facts/espera
        HStack(alignment: .top, spacing: 16) {
            leftNowPlaying
                .frame(maxWidth: .infinity, alignment: .leading)

            // ✅ Facts/espera se resuelven dentro del propio FactsView (usa el VM compartido)
            PlexNowPlayingFactsView()
                .padding(.leading, 16)   // separación extra entre columnas
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)            // evita corte contra el borde inferior del notch
    }

    // MARK: - Columna izquierda (tu UI de Now Playing compacta)
    // Si ya tienes una vista propia del player, colócala aquí.
    @ViewBuilder
    private var leftNowPlaying: some View {
        switch vm.state {
        case .ready(let np, _):
            VStack(alignment: .leading, spacing: 6) {
                // Títulos básicos como placeholder (sustituye por tu UI de player)
                Text(np.album)
                    .font(.title3).bold()
                Text(np.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .loading, .idle:
            // Placeholder mientras no hay reproducción
            VStack(alignment: .leading, spacing: 6) {
                Text("Esperando reproducción…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Error")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

