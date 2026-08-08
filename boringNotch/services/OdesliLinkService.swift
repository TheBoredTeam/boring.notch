//
//  OdesliLinkService.swift
//  boringNotch
//

import Foundation

enum ShareKind {
    case track
    case album
}

struct ShareLinkResult {
    let pageUrl: URL
}

enum ShareLinkError: Error {
    case notFound
    case network
    case rateLimited
}

final class OdesliLinkService {
    static let shared = OdesliLinkService()

    private struct CacheKey: Hashable {
        let kind: ShareKind
        let title: String
        let artist: String
        let album: String
    }

    private var cache: [CacheKey: URL] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolveShareLink(kind: ShareKind, title: String, artist: String, album: String) async throws -> ShareLinkResult {
        let key = CacheKey(kind: kind, title: title, artist: artist, album: album)
        if let cached = cache[key] {
            return ShareLinkResult(pageUrl: cached)
        }

        let sourceUrl = try await lookupAppleMusicUrl(kind: kind, title: title, artist: artist, album: album)
        let pageUrl = try await resolveOdesliPageUrl(for: sourceUrl)

        cache[key] = pageUrl
        return ShareLinkResult(pageUrl: pageUrl)
    }

    // MARK: - iTunes Search

    private func lookupAppleMusicUrl(kind: ShareKind, title: String, artist: String, album: String) async throws -> URL {
        switch kind {
        case .track:
            // Unlike .album, a wrong *edition* here is a much smaller problem
            // than for album-sharing -- it's still the same recording, just
            // possibly nested under a different collection. So if the source
            // app's reported album doesn't correlate with anything (e.g. it's
            // a generic/bogus playlist name some non-Apple/Spotify sources
            // report instead of a real album), still accept a plain
            // title+artist exact match rather than failing outright.
            let track = try await lookupSong(title: title, artist: artist, preferredAlbum: album, allowTitleOnlyFallback: true)
            guard let url = URL(string: track.trackViewUrl) else { throw ShareLinkError.notFound }
            return url
        case .album:
            // Apple's "album" entity search ranks reissues/remasters (e.g. a
            // catalog title like "Californication (Remastered)" that doesn't
            // exactly match the plain "Californication" metadata we get from
            // the OS) poorly for freeform "album artist" queries — the real
            // album often doesn't even appear in the top results. Piggyback
            // on the song search instead: the currently-playing track search
            // reliably returns its correct parent album, which we know is
            // right because it just matched by title.
            if let track = try? await lookupSong(title: title, artist: artist, preferredAlbum: album),
               let trackUrl = URL(string: track.trackViewUrl) {
                return stripQuery(from: trackUrl)
            }
            return try await lookupAlbum(artist: artist, album: album)
        }
    }

    private struct SongMatch {
        let trackViewUrl: String
    }

    /// A single track title can exist under many releases (the original single,
    /// the studio album, "Greatest Hits" compilations, remix EPs, ...), and
    /// iTunes Search doesn't rank the one the user is actually listening to
    /// first. Requires the result's album to loosely correlate with
    /// `preferredAlbum` -- see `bestMatch` for why a bare title/artist match is
    /// unsafe on its own (mood playlists and "Various Artists" compilations
    /// routinely carry an exact title+artist credit too).
    private func lookupSong(title: String, artist: String, preferredAlbum: String, allowTitleOnlyFallback: Bool = false) async throws -> SongMatch {
        let results = try await search(term: "\(title) \(artist)", entity: "song", limit: 10)

        var match = bestMatch(in: results, title: title, artist: artist, preferredAlbum: preferredAlbum)

        if match == nil && allowTitleOnlyFallback && !preferredAlbum.isEmpty {
            match = bestMatch(in: results, title: title, artist: artist, preferredAlbum: "")
            if match != nil {
                print("OdesliLinkService: no album-correlated match for title=\"\(title)\" artist=\"\(artist)\" preferredAlbum=\"\(preferredAlbum)\"; using title/artist-only match instead")
            }
        }

        guard let match else {
            let names = results.prefix(5).compactMap { $0["trackName"] as? String }
            print("OdesliLinkService: no iTunes song match for title=\"\(title)\" artist=\"\(artist)\" preferredAlbum=\"\(preferredAlbum)\", top candidates: \(names)")
            throw ShareLinkError.notFound
        }

        guard let trackViewUrl = match["trackViewUrl"] as? String else {
            print("OdesliLinkService: matched song result missing trackViewUrl for title=\"\(title)\" artist=\"\(artist)\": \(match)")
            throw ShareLinkError.notFound
        }

        return SongMatch(trackViewUrl: trackViewUrl)
    }

    /// Real catalog album names almost never equal the OS-reported plain album
    /// string exactly -- they carry suffixes/qualifiers ("(Deluxe Version)",
    /// "[Remastered 2006]", "(Remastered)") the OS metadata doesn't. Comparing
    /// with strict equality means the *correct* album routinely loses to an
    /// unrelated result that just happens to have an exact title+artist credit
    /// (mood playlists, "Various Artists" compilations, etc. all include the
    /// original recording). So: strip all bracket/paren groups + punctuation
    /// before comparing, and require correlation (containment either way) on
    /// whatever's left, not exact equality. A track/artist with no album
    /// context at all is the only case allowed to match on title+artist alone.
    private func bestMatch(in results: [[String: Any]], title: String, artist: String, preferredAlbum: String) -> [String: Any]? {
        let normalizedTitle = normalizeLoose(title)

        return results.first { result in
            guard matches(result["artistName"], artist),
                  let trackName = result["trackName"] as? String,
                  normalizeLoose(trackName) == normalizedTitle else {
                return false
            }
            guard !preferredAlbum.isEmpty else { return true }

            guard let collectionName = result["collectionName"] as? String else { return false }
            let normalizedCollection = normalizeLoose(collectionName)
            let normalizedAlbum = normalizeLoose(preferredAlbum)
            return normalizedCollection.contains(normalizedAlbum) || normalizedAlbum.contains(normalizedCollection)
        }
    }

    private func lookupAlbum(artist: String, album: String) async throws -> URL {
        let results = try await search(term: "\(album) \(artist)", entity: "album", limit: 5)

        let normalizedAlbum = normalizeLoose(album)
        // Unlike the song path, don't fall back to an unmatched first result here —
        // an album entirely absent from these results is better reported as "not
        // found" than silently swapped for an unrelated one.
        guard let match = results.first(where: { result in
            guard matches(result["artistName"], artist), let collectionName = result["collectionName"] as? String else { return false }
            let normalizedCollection = normalizeLoose(collectionName)
            return normalizedCollection.contains(normalizedAlbum) || normalizedAlbum.contains(normalizedCollection)
        }) else {
            let names = results.compactMap { $0["collectionName"] as? String }
            print("OdesliLinkService: no iTunes album match for album=\"\(album)\" artist=\"\(artist)\", candidates: \(names)")
            throw ShareLinkError.notFound
        }

        guard let urlString = match["collectionViewUrl"] as? String, let url = URL(string: urlString) else {
            print("OdesliLinkService: matched album result missing collectionViewUrl for album=\"\(album)\" artist=\"\(artist)\": \(match)")
            throw ShareLinkError.notFound
        }

        return url
    }

    /// Used for artist comparisons only. Loose/containment rather than exact --
    /// the same recording is routinely credited differently across catalog
    /// entries (band vs. solo credit: "The Jimi Hendrix Experience" on the
    /// real studio album vs. "Jimi Hendrix" the OS reports; "feat." credits;
    /// "The Beatles" vs "Beatles"), so exact equality throws out the correct
    /// candidate over a naming technicality.
    private func matches(_ value: Any?, _ expected: String) -> Bool {
        guard let value = value as? String else { return false }
        let lhs = normalizeLoose(value)
        let rhs = normalizeLoose(expected)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs.contains(rhs) || rhs.contains(lhs)
    }

    /// Strips bracket/paren groups anywhere in the string (not just trailing --
    /// catalog titles like "High Times (Singles 1992-2006) [Remastered 2006]"
    /// wrap the meaningful part in parens too), then collapses punctuation and
    /// case so "High Times: Singles 1992-2006" and "High Times (Singles
    /// 1992-2006) [Remastered 2006]" both reduce to "high times singles 1992
    /// 2006"-ish strings whose containment can be compared.
    private func normalizeLoose(_ s: String) -> String {
        var result = s.replacingOccurrences(of: "[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "[^\\w]+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func stripQuery(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    private func search(term: String, entity: String, limit: Int) async throws -> [[String: Any]] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            print("OdesliLinkService: failed to build iTunes Search URL for term=\"\(term)\" entity=\(entity)")
            throw ShareLinkError.notFound
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            print("OdesliLinkService: iTunes Search request failed for \(url.absoluteString): \(error)")
            throw ShareLinkError.network
        }

        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            print("OdesliLinkService: iTunes Search rate-limited (429) for \(url.absoluteString), headers: \(http.allHeaderFields), body: \(String(data: data, encoding: .utf8) ?? "<undecodable>")")
            throw ShareLinkError.rateLimited
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("OdesliLinkService: iTunes Search returned status \(status) for \(url.absoluteString), body: \(String(data: data, encoding: .utf8) ?? "<undecodable>")")
            throw ShareLinkError.notFound
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            print("OdesliLinkService: couldn't decode iTunes Search response for \(url.absoluteString), body: \(String(data: data, encoding: .utf8) ?? "<undecodable>")")
            throw ShareLinkError.notFound
        }

        return results
    }

    // MARK: - Odesli

    private func resolveOdesliPageUrl(for sourceUrl: URL) async throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.song.link"
        components.path = "/v1-alpha.1/links"
        components.queryItems = [
            URLQueryItem(name: "url", value: sourceUrl.absoluteString)
        ]

        guard let odesliUrl = components.url else {
            print("OdesliLinkService: failed to build Odesli URL for source \(sourceUrl.absoluteString)")
            throw ShareLinkError.notFound
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: odesliUrl)
        } catch {
            print("OdesliLinkService: Odesli request failed for \(odesliUrl.absoluteString): \(error)")
            throw ShareLinkError.network
        }

        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            print("OdesliLinkService: Odesli rate-limited (429) for \(odesliUrl.absoluteString), headers: \(http.allHeaderFields), body: \(String(data: data, encoding: .utf8) ?? "<undecodable>")")
            throw ShareLinkError.rateLimited
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("OdesliLinkService: Odesli returned status \(status) for \(odesliUrl.absoluteString), body: \(String(data: data, encoding: .utf8) ?? "<undecodable>")")
            throw ShareLinkError.notFound
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pageUrlString = json["pageUrl"] as? String,
              let pageUrl = URL(string: pageUrlString) else {
            print("OdesliLinkService: couldn't decode Odesli response for \(odesliUrl.absoluteString), body: \(String(data: data, encoding: .utf8) ?? "<undecodable>")")
            throw ShareLinkError.notFound
        }

        return pageUrl
    }
}
