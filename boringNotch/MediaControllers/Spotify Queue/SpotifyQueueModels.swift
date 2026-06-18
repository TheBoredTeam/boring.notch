//
//  SpotifyQueueModels.swift
//  boringNotch
//

import Foundation

enum SpotifyQueueAuthState: Equatable {
    case unauthenticated
    case authenticating
    case authenticated
    case failed(String)
}

struct SpotifyQueueItem: Identifiable, Equatable, Sendable {
    let id: String
    let uri: String?
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let isCurrentlyPlaying: Bool

    var canPlay: Bool {
        guard let uri, !uri.isEmpty else { return false }
        return !isCurrentlyPlaying
    }
}

struct SpotifyTokenResponse: Decodable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

struct SpotifyQueueResponse: Decodable, Sendable {
    let currentlyPlaying: SpotifyQueueItemPayload?
    let queue: [SpotifyQueueItemPayload]

    enum CodingKeys: String, CodingKey {
        case currentlyPlaying = "currently_playing"
        case queue
    }
}

struct SpotifyQueueItemPayload: Decodable, Sendable {
    let type: String?
    let name: String?
    let uri: String?
    let id: String?
    let artists: [SpotifyArtistPayload]?
    let album: SpotifyAlbumPayload?
    let show: SpotifyShowPayload?

    var displayTitle: String {
        if type == "episode", let episodeName = name {
            return episodeName
        }
        return name ?? "Unknown"
    }

    var displaySubtitle: String {
        if type == "episode" {
            return show?.publisher ?? show?.name ?? "Podcast"
        }
        let names = artists?.compactMap(\.name).filter { !$0.isEmpty } ?? []
        return names.isEmpty ? "Unknown Artist" : names.joined(separator: ", ")
    }

    var artworkURL: URL? {
        if type == "episode" {
            if let urlString = show?.images?.first?.url {
                return URL(string: urlString)
            }
        }
        if let urlString = album?.images?.first?.url {
            return URL(string: urlString)
        }
        return nil
    }

    var stableID: String {
        let fallbackID = [type, name, displaySubtitle]
            .compactMap { $0?.normalizedQueueComparisonText }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return uri ?? id ?? (fallbackID.isEmpty ? "unknown-queue-item" : fallbackID)
    }
}

struct SpotifyArtistPayload: Decodable, Sendable {
    let name: String?
}

struct SpotifyAlbumPayload: Decodable, Sendable {
    let name: String?
    let images: [SpotifyImagePayload]?
}

struct SpotifyShowPayload: Decodable, Sendable {
    let name: String?
    let publisher: String?
    let images: [SpotifyImagePayload]?
}

struct SpotifyImagePayload: Decodable, Sendable {
    let url: String?
    let height: Int?
    let width: Int?
}

enum SpotifyAPIError: LocalizedError, Sendable {
    case notConfigured
    case notAuthenticated
    case noActiveDevice
    case invalidURL
    case invalidResponse
    case httpError(Int, String?)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Spotify client ID is not configured."
        case .notAuthenticated:
            return "Spotify session expired. Connect again in Settings."
        case .noActiveDevice:
            return "Start playing something in Spotify to see your queue."
        case .invalidURL:
            return "Invalid Spotify API URL."
        case .invalidResponse:
            return "Invalid response from Spotify."
        case .httpError(let code, let message):
            if (500..<600).contains(code) {
                return "Spotify is temporarily unavailable. Try again in a moment."
            }
            if let message, !message.isEmpty {
                return "Spotify API error (\(code)): \(message)"
            }
            return "Spotify API error (\(code))."
        case .decodingFailed:
            return "Could not read Spotify queue data."
        }
    }
}

enum SpotifyConfig {
    static let authorizationScopes = [
        "user-read-currently-playing",
        "user-read-playback-state",
        "user-modify-playback-state",
    ].joined(separator: " ")

    static let loopbackRedirectBase = "http://127.0.0.1"
    static let loopbackRedirectPort: UInt16 = 8765
    static let loopbackRedirectPath = "/callback"

    static var loopbackRedirectURI: String {
        "\(loopbackRedirectBase):\(loopbackRedirectPort)\(loopbackRedirectPath)"
    }

    static var clientID: String {
        if let id = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String,
           !id.isEmpty,
           id != "$(SPOTIFY_CLIENT_ID)" {
            return id
        }
        return ""
    }

    static var isConfigured: Bool {
        !clientID.isEmpty
    }
}

extension SpotifyQueueResponse {
    func toQueueItems() -> [SpotifyQueueItem] {
        var items: [SpotifyQueueItem] = []
        if let current = currentlyPlaying {
            items.append(
                SpotifyQueueItem(
                    id: current.stableID,
                    uri: current.uri,
                    title: current.displayTitle,
                    subtitle: current.displaySubtitle,
                    artworkURL: current.artworkURL,
                    isCurrentlyPlaying: true
                )
            )
        }
        for entry in queue {
            items.append(
                SpotifyQueueItem(
                    id: entry.stableID,
                    uri: entry.uri,
                    title: entry.displayTitle,
                    subtitle: entry.displaySubtitle,
                    artworkURL: entry.artworkURL,
                    isCurrentlyPlaying: false
                )
            )
        }
        return items
    }
}

extension Array where Element == SpotifyQueueItem {
    func reconciledWithCurrentPlayback(title: String, subtitle: String, artworkURL: URL?) -> [SpotifyQueueItem] {
        guard !isEmpty else { return self }

        let normalizedTitle = title.normalizedQueueComparisonText
        guard !normalizedTitle.isEmpty, normalizedTitle != "unknown" else { return self }

        let normalizedSubtitle = subtitle.normalizedQueueComparisonText
        let titleMatches = enumerated().filter {
            $0.element.title.normalizedQueueComparisonText == normalizedTitle
        }
        let exactMatches = titleMatches.filter {
            normalizedSubtitle.isEmpty || $0.element.subtitle.normalizedQueueComparisonText == normalizedSubtitle
        }

        if let selectedIndex = exactMatches.first?.offset ?? (titleMatches.count == 1 ? titleMatches[0].offset : nil) {
            return enumerated().map { index, item in
                item.withCurrentlyPlaying(index == selectedIndex)
            }
        }

        if let currentIndex = firstIndex(where: \.isCurrentlyPlaying) {
            var items = map { $0.withCurrentlyPlaying(false) }
            items[currentIndex] = SpotifyQueueItem(
                id: "current-\(normalizedTitle)-\(normalizedSubtitle)",
                uri: nil,
                title: title,
                subtitle: subtitle,
                artworkURL: artworkURL,
                isCurrentlyPlaying: true
            )
            return items
        }

        return self
    }
}

private extension SpotifyQueueItem {
    func withCurrentlyPlaying(_ isCurrentlyPlaying: Bool) -> SpotifyQueueItem {
        SpotifyQueueItem(
            id: id,
            uri: uri,
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            isCurrentlyPlaying: isCurrentlyPlaying
        )
    }
}

private extension String {
    var normalizedQueueComparisonText: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
