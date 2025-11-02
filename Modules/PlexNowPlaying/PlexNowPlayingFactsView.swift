//
//  PlexNowPlayingFactsView.swift
//  boringNotch (Plex Module)
//

import SwiftUI

public struct PlexNowPlayingFactsView: View {

    // VM centralizado del módulo Plex
    @ObservedObject private var vm = PlexNowPlayingViewModel.shared

    /// Para previews o inyección externa de facts (opcional)
    public var injectedFacts: AlbumFacts?

    public init(injectedFacts: AlbumFacts? = nil) {
        self.injectedFacts = injectedFacts
    }

    // MARK: - UI

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let facts = resolveFacts() {
                Text("Detalles del álbum")
                    .font(.headline)

                // Campos básicos (usa los nombres del único `AlbumFacts` válido)
                factRow("Lanzamiento", facts.releaseDate ?? "—")
                factRow("Sello", facts.label ?? "—")

                if !facts.producers.isEmpty {
                    factRow("Productores", facts.producers.joined(separator: ", "))
                }
                if !facts.personnel.isEmpty {
                    factRow("Créditos", facts.personnel.joined(separator: ", "))
                }

                if !facts.sources.isEmpty {
                    factRow("Fuentes", facts.sources.joined(separator: " · "))
                }

                if let summary = facts.summaryMD?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !summary.isEmpty {
                    Divider().opacity(0.2)
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else {
                Text("Sin información del álbum")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - Resolve source

    /// Toma facts inyectados (si hay) o los del estado del VM.
    private func resolveFacts() -> AlbumFacts? {
        if let injectedFacts { return injectedFacts }
        if case .ready(let f) = vm.state { return f }     // ✅ Sin tupla
        return nil
    }

    // MARK: - Row helper

    @ViewBuilder
    private func factRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title + ":")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}
