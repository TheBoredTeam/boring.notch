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

    /// Si quieres forzar el título del álbum cuando uses `injectedFacts`
    public var injectedAlbumTitle: String?

    public init(injectedFacts: AlbumFacts? = nil, injectedAlbumTitle: String? = nil) {
        self.injectedFacts = injectedFacts
        self.injectedAlbumTitle = injectedAlbumTitle
    }

    public var body: some View {
        // Scroll para que no se corte info larga
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                if let facts = resolveFacts() {
                    // Título: nombre del álbum
                    Text(currentAlbumTitle())
                        .font(.headline)

                    // Campos básicos
                    factRow("Lanzamiento", facts.releaseDate ?? "—")
                    factRow("Sello", facts.label ?? "—")
                    if let country = facts.country {
                        factRow("País", country)
                    }
                    if let genres = facts.genres, !genres.isEmpty {
                        factRow("Género", genres.joined(separator: ", "))
                    }

                    if !facts.producers.isEmpty {
                        factRow("Productores", facts.producers.joined(separator: ", "))
                    }
                    if !facts.personnel.isEmpty {
                        factRow("Créditos", facts.personnel.joined(separator: ", "))
                    }

                    // Notas (si existen)
                    if let notes = facts.notes,
                       !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Divider().opacity(0.2)
                        Text(notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    // Fuentes (Discogs.com clicable)
                    if let link = firstValidURL(from: facts.sources) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Fuentes:")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 110, alignment: .leading)

                            Link(labelFor(url: link), destination: link)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
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
    }

    // MARK: - Resolve

    private func resolveFacts() -> AlbumFacts? {
        if let injectedFacts { return injectedFacts }
        if case .ready(let f) = vm.state { return f }
        return nil
    }

    private func currentAlbumTitle() -> String {
        if let injectedAlbumTitle, !injectedAlbumTitle.isEmpty {
            return injectedAlbumTitle
        }
        if let np = vm.snapshotNowPlaying, !np.album.isEmpty {
            return np.album
        }
        // Fallback si no hay álbum disponible aún
        return "Detalles del álbum"
    }

    // MARK: - Helpers UI

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

    private func firstValidURL(from sources: [String]) -> URL? {
        for s in sources {
            if let u = URL(string: s) { return u }
        }
        return nil
    }

    private func labelFor(url: URL) -> String {
        // Siempre “Discogs.com” cuando el host contenga discogs (api.discogs.com, discogs.com, etc.)
        if (url.host ?? "").lowercased().contains("discogs") {
            return "Discogs.com"
        }
        // Otros dominios: muestra el host sin www
        let host = (url.host ?? "").replacingOccurrences(of: "www.", with: "")
        return host.isEmpty ? url.absoluteString : host
    }
}
