//
//  DiscogsClient.swift
//  boringNotch (Plex Module)
//

import Foundation
import Defaults

public final class DiscogsClient: @unchecked Sendable {

    public static let shared = DiscogsClient()
    private init() {}

    private let baseSearchURL = URL(string: "https://api.discogs.com/database/search")!

    private struct SearchResponse: Decodable {
        let results: [Result]
        struct Result: Decodable {
            let type: String?
            let title: String?
            let country: String?
            let year: String?
            let label: [String]?
            let catno: String?
        }
    }

    public func fetchFacts(artist: String, album: String) async throws -> AlbumFacts? {
        // Usa únicamente las Keys definidas en Defaults+Discogs.swift
        let enabled = Defaults[.enableDiscogs]
        let token   = Defaults[.discogsToken].trimmingCharacters(in: .whitespacesAndNewlines)

        guard enabled, !token.isEmpty else { return nil }

        var comps = URLComponents(url: baseSearchURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "artist", value: artist),
            .init(name: "release_title", value: album),
            .init(name: "type", value: "release"),
            .init(name: "per_page", value: "5"),
            .init(name: "page", value: "1"),
            .init(name: "token", value: token)
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue("boringNotch/1.0", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        let first = decoded.results.first { ($0.type ?? "").lowercased() == "release" } ?? decoded.results.first
        guard let r = first else { return nil }

        return AlbumFacts(
            releaseDate: r.year,
            label: r.label?.first,
            producers: [],
            personnel: [],
            country: r.country,
            catalogNumber: r.catno,
            chartPeaks: nil,
            sources: [comps.url?.absoluteString ?? "https://api.discogs.com"],
            summaryMD: ""
        )
    }
}
