//
//  FactsClient.swift
//  BoringNotch (Plex Module)
//

import Foundation

public struct AlbumFacts: Codable, Sendable {
    public let releaseDate: String?
    public let label: String?
    public let producers: [String]
    public let personnel: [String]
    public let chartPeaks: [[String:String]]?
    public let sources: [String]
    public let wikiLang: String?
    public let summaryMD: String
}

public final class FactsClient {
    private let apiBase: URL
    private let debugLogging: Bool

    public init(apiBase: URL, debugLogging: Bool = false) {
        self.apiBase = apiBase
        self.debugLogging = debugLogging
    }

    public func enrich(artist: String, album: String, albumMBIDs: [String]) async throws -> AlbumFacts {
        let url = apiBase.appendingPathComponent("/enrich")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = EnrichIn(artist: artist, album: album, album_mbids: albumMBIDs)
        req.httpBody = try JSONEncoder().encode(payload)

        if debugLogging {
            print("🧠 [FactsClient] POST \(url.absoluteString)")
            print("🧠 [FactsClient] → payload: artist=\(artist) album=\(album) mbids=\(albumMBIDs.count)")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1

        if debugLogging {
            print("🧠 [FactsClient] ← status=\(code) bytes=\(data.count)")
        }

        guard code == 200 else {
            throw NSError(domain: "FactsClient", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }

        let facts = try JSONDecoder().decode(AlbumFacts.self, from: data)

        if debugLogging {
            print("🧠 [FactsClient] Decodificado: releaseDate=\(facts.releaseDate ?? "-") label=\(facts.label ?? "-") sources=\(facts.sources.count)")
        }

        return facts
    }

    private struct EnrichIn: Codable { let artist: String; let album: String; let album_mbids: [String] }
}

