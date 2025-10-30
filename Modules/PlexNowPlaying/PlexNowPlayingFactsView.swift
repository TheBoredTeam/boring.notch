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
            case .idle:
                waitingRight()

            case .loading(let np):
                VStack(alignment: .leading, spacing: 8) {
                    header(np)
                    ProgressView()
                }

            case .loaded(let np, let facts):
                factsPanel(np: np, facts: facts)

            case .error(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Error").font(.headline).foregroundStyle(.secondary)
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(minWidth: 240, maxWidth: .infinity, alignment: .topLeading)
    }

    private func header(_ np: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(np.album).font(.headline).lineLimit(2)
            Text(np.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
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
            Text("Esperando reproducción…").font(.headline).foregroundStyle(.secondary)
            Text("Aquí verás sello, fecha, créditos y fuentes del álbum.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func factsPanel(np: NowPlaying, facts: AlbumFacts) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header(np)

                if let date = facts.releaseDate, !date.isEmpty {
                    factRow("Lanzamiento:", date)
                }
                if let label = facts.label, !label.isEmpty {
                    factRow("Sello:", label)
                }
                if !facts.producers.isEmpty {
                    factRow("Productores:", facts.producers.joined(separator: ", ")).lineLimit(3)
                }
                if !facts.personnel.isEmpty {
                    factRow("Créditos:", facts.personnel.joined(separator: ", ")).lineLimit(5)
                }
                if let peaks = facts.chartPeaks, !peaks.isEmpty {
                    let compact = peaks.map { "\($0["country"] ?? "-"): \($0["peak"] ?? "-")" }.joined(separator: " · ")
                    factRow("Charts:", compact)
                }
                if !facts.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fuentes:").font(.subheadline).bold()
                        ForEach(facts.sources, id: \.self) { s in
                            if let url = URL(string: s) {
                                Link(s, destination: url).font(.caption)
                            } else {
                                Text(s).font(.caption)
                            }
                        }
                    }
                }

                let summary = facts.summaryMD.trimmingCharacters(in: .whitespacesAndNewlines)
                if !summary.isEmpty {
                    Divider().padding(.vertical, 4)
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 2)
        }
    }

    private func factRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.subheadline).bold()
                .frame(width: 110, alignment: .leading)
            Text(value).font(.subheadline)
        }
    }
}
