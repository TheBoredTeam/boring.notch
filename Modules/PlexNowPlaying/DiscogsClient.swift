//
//  DiscogsClient.swift
//  boringNotch (Plex Module)
//

import Foundation
import Defaults

// MARK: - Helpers

private enum StringOrInt: Decodable {
    case string(String)
    case int(Int)
    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .int(let i):    return String(i)
        }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else {
            throw DecodingError.typeMismatch(
                StringOrInt.self,
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Expected String or Int for year")
            )
        }
    }
}

@inline(__always)
private func normalizeDiscogsWebURL(_ s: String) -> String {
    // Garantiza URL absoluta hacia www.discogs.com
    if s.hasPrefix("http://") || s.hasPrefix("https://") { return s }
    if s.hasPrefix("//") { return "https:" + s }
    if s.hasPrefix("/")  { return "https://www.discogs.com" + s }
    return "https://www.discogs.com/" + s
}

// MARK: - Client

final class DiscogsClient: @unchecked Sendable {

    static let shared = DiscogsClient()
    private init() {}

    func fetchFacts(artist: String, album: String) async -> AlbumFacts? {
        guard Defaults[.enableDiscogs] else { return nil }

        let token = Defaults[.discogsToken].trimmingCharacters(in: .whitespacesAndNewlines)
        let userAgent = "boringNotch/1.0 (DiscogsClient; +https://github.com/your-org/boringNotch)"

        guard let searchURL = buildSearchURL(artist: artist, album: album, token: token) else { return nil }

        var req = URLRequest(url: searchURL)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let search = try JSONDecoder().decode(DiscogsSearchResponse.self, from: data)
            guard let best = pickBestResult(from: search.results) else { return nil }

            // Preferimos `uri` (web). Si viene relativa, la normalizamos.
            var sources: [String] = []
            if let uri = best.uri?.trimmingCharacters(in: .whitespacesAndNewlines), !uri.isEmpty {
                sources.append(normalizeDiscogsWebURL(uri))
            } else if let resource = best.resource_url {
                sources.append(resource) // fallback
            }

            var facts = AlbumFacts(
                releaseDate: best.year?.stringValue,
                label: best.label?.first,
                producers: [],
                personnel: [],
                country: best.country,
                genres: mergeGenres(base: best.genre, styles: best.style),
                notes: nil,
                catalogNumber: best.catno,
                chartPeaks: nil,
                sources: sources,
                summaryMD: nil
            )

            // Release completo
            if let releaseFacts = try await fetchReleaseDetailsIfPossible(from: best, userAgent: userAgent) {
                facts.releaseDate   = releaseFacts.releaseDate   ?? facts.releaseDate
                facts.label         = releaseFacts.label         ?? facts.label
                facts.country       = releaseFacts.country       ?? facts.country
                facts.catalogNumber = releaseFacts.catalogNumber ?? facts.catalogNumber
                facts.genres        = releaseFacts.genres        ?? facts.genres
                facts.notes         = releaseFacts.notes         ?? facts.notes
                facts.sources       = Array(Set(facts.sources + releaseFacts.sources))
            }

            return facts
        } catch {
            #if DEBUG
            print("[Discogs] error: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Internals

    private func buildSearchURL(artist: String, album: String, token: String) -> URL? {
        var comps = URLComponents(string: "https://api.discogs.com/database/search")
        var items: [URLQueryItem] = [
            .init(name: "artist", value: artist),
            .init(name: "release_title", value: album),
            .init(name: "type", value: "release"),
            .init(name: "per_page", value: "5")
        ]
        if !token.isEmpty {
            items.append(.init(name: "token", value: token))
        }
        comps?.queryItems = items
        return comps?.url
    }

    private func pickBestResult(from results: [DiscogsSearchResult]) -> DiscogsSearchResult? {
        results.first(where: { $0.type == "release" }) ?? results.first
    }

    private func fetchReleaseDetailsIfPossible(from result: DiscogsSearchResult,
                                               userAgent: String) async throws -> AlbumFacts? {
        guard let urlString = result.resource_url,
              urlString.contains("/releases/"),
              let url = URL(string: urlString) else {
            return nil
        }

        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: req)
        let release = try JSONDecoder().decode(DiscogsRelease.self, from: data)

        var sources: [String] = []
        if let uri = release.uri?.trimmingCharacters(in: .whitespacesAndNewlines), !uri.isEmpty {
            sources.append(normalizeDiscogsWebURL(uri))
        } else {
            sources.append(urlString) // fallback a API
        }

        let releaseDate = release.released ?? release.year?.stringValue
        let labelName   = release.labels?.first?.name
        let catno       = release.labels?.first?.catno
        let genres      = mergeGenres(base: release.genres, styles: release.styles)
        let notes       = release.notes?.trimmingCharacters(in: .whitespacesAndNewlines)

        return AlbumFacts(
            releaseDate: releaseDate,
            label: labelName,
            producers: [],
            personnel: [],
            country: release.country,
            genres: genres,
            notes: notes,
            catalogNumber: catno,
            chartPeaks: nil,
            sources: sources,
            summaryMD: nil
        )
    }

    private func mergeGenres(base: [String]?, styles: [String]?) -> [String]? {
        let all = (base ?? []) + (styles ?? [])
        let trimmed = all.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let uniques = Array(NSOrderedSet(array: trimmed)).compactMap { $0 as? String }
        return uniques.isEmpty ? nil : uniques
    }
}

// MARK: - DTOs

private struct DiscogsSearchResponse: Decodable {
    let results: [DiscogsSearchResult]
}

private struct DiscogsSearchResult: Decodable {
    let type: String?
    let title: String?
    let country: String?
    let genre: [String]?
    let style: [String]?
    let year: StringOrInt?
    let label: [String]?
    let catno: String?
    let resource_url: String?
    let uri: String?
}

private struct DiscogsRelease: Decodable {
    let id: Int?
    let country: String?
    let year: StringOrInt?
    let released: String?
    let genres: [String]?
    let styles: [String]?
    let notes: String?
    let labels: [DiscogsReleaseLabel]?
    let uri: String?
}

private struct DiscogsReleaseLabel: Decodable {
    let name: String?
    let catno: String?
}
