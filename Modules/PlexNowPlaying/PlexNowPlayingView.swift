//
//  PlexNowPlayingView.swift
//  boringNotch (Plex Module)
//

import SwiftUI

public struct PlexNowPlayingView: View {

    @ObservedObject private var vm = PlexNowPlayingViewModel.shared

    public init() {}

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            nowPlayingCompact()
                .frame(maxWidth: .infinity, alignment: .leading)

            // Columna derecha: detalles del álbum (facts)
            PlexNowPlayingFactsView()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func nowPlayingCompact() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let np = vm.snapshotNowPlaying {
                // Título (usamos el nombre del álbum) y artista
                Text(np.album)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(np.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Estado de facts
                HStack(spacing: 8) {
                    switch vm.state {
                    case .idle:
                        Label("Cargando…", systemImage: "hourglass")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    case .loading:
                        ProgressView()
                            .scaleEffect(0.8)
                    case .ready:
                        Label("Listo", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                    case .error:
                        Label("Error", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }
            } else {
                // Sin reproducción
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sin reproducción")
                        .font(.title3.weight(.semibold))
                    Text("Inicia playback en Plexamp para ver detalles.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
