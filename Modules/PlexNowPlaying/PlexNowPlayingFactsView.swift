//
//  PlexNowPlayingFactsView.swift
//  BoringNotch (Plex Module)
//

import SwiftUI

public struct PlexNowPlayingFactsView: View {

    @ObservedObject private var vm = PlexNowPlayingViewModel.shared

    public init() {}

    public var body: some View {
        Group {
            switch vm.state {
            case .idle, .loading:
                proportionalTwoColumn(
                    left: nowPlayingCompactPlaceholder(),
                    right: waitingRight()
                )

            case .error(let message):
                proportionalTwoColumn(
                    left: nowPlayingCompact(),
                    right: VStack(alignment: .leading, spacing: 6) {
                        Text("Error")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                )

            case .ready(let np, let facts):
                proportionalTwoColumn(
                    left: nowPlayingCompact(),
                    right: factsColumn(nowPlaying: np, facts: facts)
                )
            }
        }
        // Eleva el bloque para evitar cortes y solapamientos con controles
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    // MARK: - Layout proporcional (≈60% / 40%)
    /// Izquierda: ~60% (espacio para tu Now Playing)
    /// Derecha:   ~40% (facts) — ~20% más ancho vs. mitad a mitad
    @ViewBuilder
    private func proportionalTwoColumn<L: View, R: View>(left: L, right: R) -> some View {
        GeometryReader { proxy in
            let total = proxy.size.width
            // Ajusta proporciones aquí si lo quieres más fino
            let rightWidth = max(260, total * 0.40)   // columna de texto ~40% (mínimo útil)
            let leftWidth  = max(0, total - rightWidth)

            HStack(alignment: .top, spacing: 22) {
                left
                    .frame(width: leftWidth, alignment: .leading)    // controles/now playing (renderizas fuera)
                    .allowsHitTesting(false)                          // no intercepta gestos del player

                right
                    .frame(width: rightWidth, alignment: .leading)
                    .padding(.leading, 12)                            // separación visual
                    .padding(.trailing, 8)
            }
            .frame(width: total, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Placeholders izquierda (tu UI principal pinta el player)
    @ViewBuilder
    private func nowPlayingCompact() -> some View {
        Color.clear.frame(height: 1)
    }

    @ViewBuilder
    private func nowPlayingCompactPlaceholder() -> some View {
        Color.clear.frame(height: 1)
    }

    // MARK: - Mensaje de espera (derecha)
    @ViewBuilder
    private func waitingRight() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cargando…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Facts (derecha)
    @ViewBuilder
    private func factsColumn(nowPlaying np: NowPlaying, facts: AlbumFacts) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Encabezado derecho
            Text(np.album)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            Text(np.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Divider().opacity(0.35)

            VStack(alignment: .leading, spacing: 6) {
                if let label = facts.label, !label.isEmpty {
                    factLine("Sello:", label)
                }
                if let date = facts.releaseDate, !date.isEmpty {
                    factLine("Lanzamiento:", date)
                }

                // Estos campos son [String] no opcionales
                let producers = facts.producers
                if !producers.isEmpty {
                    factLine("Prod.:", producers.joined(separator: ", "))
                }

                let personnel = facts.personnel
                if !personnel.isEmpty {
                    factLine("Créditos:", personnel.joined(separator: ", "))
                }

                let sources = facts.sources
                if let first = sources.first, let url = URL(string: first) {
                    Link(first.lowercased().contains("wiki") ? "Wikipedia" : first,
                         destination: url)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    @ViewBuilder
    private func factLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .fixedSize() // no se comprime la etiqueta

            Text(value)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
