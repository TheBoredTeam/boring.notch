//
//  PlexNowPlayingView.swift
//  BoringNotch (Plex Module)
//

import SwiftUI

public struct PlexNowPlayingView: View {

    @ObservedObject private var vm = PlexNowPlayingViewModel.shared

    public init() {}

    public var body: some View {
        // Dos columnas: izquierda "Now Playing", derecha "Facts / Estado"
        HStack(alignment: .top, spacing: 16) {
            leftColumn()
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)

            rightColumn()
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }

    // MARK: - Columnas

    @ViewBuilder
    private func leftColumn() -> some View {
        switch vm.state {
        case .idle:
            placeholderNowPlaying()

        case .loading(let np):
            nowPlayingCompact(np)
                .overlay(alignment: .topTrailing) { ProgressView().controlSize(.small) }

        case .loaded(let np, _):
            nowPlayingCompact(np)

        case .error:
            placeholderNowPlaying()
        }
    }

    @ViewBuilder
    private func rightColumn() -> some View {
        switch vm.state {
        case .idle:
            waitingRight()

        case .loading:
            VStack(alignment: .leading, spacing: 8) {
                Text("Buscando datos del álbum…").font(.headline)
                ProgressView()
            }

        case .loaded(_, let facts):
            factsPanel(facts)

        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Error").font(.headline).foregroundStyle(.secondary)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Subvistas

    private func placeholderNowPlaying() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing playing")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Reproduce algo en Plexamp para ver los datos aquí.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func nowPlayingCompact(_ np: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(np.album).font(.title3).bold().lineLimit(2)
            Text(np.artist).font(.headline).foregroundStyle(.secondary).lineLimit(1)

            if let mbids = np.albumMBIDs, !mbids.isEmpty {
                Text("MBIDs: \(mbids.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func waitingRight() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Esperando reproducción…")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Cuando empiece a sonar un álbum, aquí verás sello, fecha, créditos y fuentes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func factsPanel(_ facts: AlbumFacts) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let date = facts.releaseDate, !date.isEmpty {
                    factLine("Lanzamiento:", date)
                }
                if let label = facts.label, !label.isEmpty {
                    factLine("Sello:", label)
                }
                if !facts.producers.isEmpty {
                    factLine("Productores:", facts.producers.joined(separator: ", "))
                        .lineLimit(3)
                }
                if !facts.personnel.isEmpty {
                    factLine("Créditos:", facts.personnel.joined(separator: ", "))
                        .lineLimit(5)
                }
                if let peaks = facts.chartPeaks, !peaks.isEmpty {
                    let compact = peaks.map { "\($0["country"] ?? "-"): \($0["peak"] ?? "-")" }.joined(separator: " · ")
                    factLine("Charts:", compact)
                }
                if !facts.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fuentes:").font(.subheadline).bold()
                        ForEach(facts.sources, id: \.self) { s in
                            if let url = URL(string: s) {
                                Link(s, destination: url)
                                    .font(.caption)
                            } else {
                                Text(s).font(.caption)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func factLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).bold().frame(width: 110, alignment: .leading)
            Text(value).font(.subheadline)
        }
    }
}
