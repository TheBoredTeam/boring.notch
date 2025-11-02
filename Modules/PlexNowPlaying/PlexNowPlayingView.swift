//
//  PlexNowPlayingView.swift
//  BoringNotch (Plex Module)
//

import SwiftUI

public struct PlexNowPlayingView: View {

    @ObservedObject private var vm = PlexNowPlayingViewModel.shared

    public init() {}

    public var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func content() -> some View {
        switch vm.state {
        case .idle:
            loadingPlaceholder(title: "Reproduce algo en Plexamp…")

        case .loading:
            // ✅ No tocamos vm, usamos placeholders
            HStack(spacing: 16) {
                nowPlayingColumn(
                    title: "Buscando…",
                    subtitle: "",
                    progress: nil
                )
                Divider().opacity(0.2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Buscando datos del álbum…")
                        .foregroundStyle(.secondary)
                }
            }

        case .ready(let facts):
            HStack(spacing: 16) {
                nowPlayingColumn(
                    title: "Álbum",
                    subtitle: "Artista",
                    progress: nil
                )
                Divider().opacity(0.2)
                PlexNowPlayingFactsView(injectedFacts: facts)
            }

        case .error(let message):
            HStack(spacing: 16) {
                nowPlayingColumn(
                    title: "Álbum",
                    subtitle: "Artista",
                    progress: nil
                )
                Divider().opacity(0.2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error").font(.headline).foregroundStyle(.secondary)
                    Text(message).font(.subheadline)
                }
            }
        }
    }



    // MARK: - Subviews

    private func loadingPlaceholder(title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(title).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func nowPlayingColumn(title: String, subtitle: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let p = progress {
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .tint(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
