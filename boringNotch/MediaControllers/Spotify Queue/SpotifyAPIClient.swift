//
//  SpotifyAPIClient.swift
//  boringNotch
//

import Foundation

private struct SpotifyPlaybackOffset: Encodable {
    let position: Int
}

private struct SpotifyPlayRequest: Encodable {
    let uris: [String]
    let offset: SpotifyPlaybackOffset?
}

struct SpotifyAPIClient {
    private let session: URLSession
    private static let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func play(uri: String, accessToken: String) async throws {
        try await play(uris: [uri], selectedIndex: 0, accessToken: accessToken)
    }

    func play(uris: [String], selectedIndex: Int, accessToken: String) async throws {
        guard !uris.isEmpty, uris.indices.contains(selectedIndex) else {
            throw SpotifyAPIError.invalidURL
        }

        guard let url = URL(string: "https://api.spotify.com/v1/me/player/play") else {
            throw SpotifyAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(
            SpotifyPlayRequest(
                uris: uris,
                offset: SpotifyPlaybackOffset(position: selectedIndex)
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }

        switch http.statusCode {
        case 200, 202, 204:
            return
        case 401:
            throw SpotifyAPIError.notAuthenticated
        case 404:
            throw SpotifyAPIError.noActiveDevice
        default:
            let message = String(data: data, encoding: .utf8)
            throw SpotifyAPIError.httpError(http.statusCode, message)
        }
    }

    func fetchQueue(accessToken: String) async throws -> SpotifyQueueResponse {
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/queue") else {
            throw SpotifyAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(SpotifyQueueResponse.self, from: data)
            } catch {
                throw SpotifyAPIError.decodingFailed
            }
        case 204:
            return SpotifyQueueResponse(currentlyPlaying: nil, queue: [])
        case 401:
            throw SpotifyAPIError.notAuthenticated
        case 403:
            let message = String(data: data, encoding: .utf8)
            throw SpotifyAPIError.httpError(http.statusCode, message)
        case 404:
            throw SpotifyAPIError.noActiveDevice
        default:
            let message = String(data: data, encoding: .utf8)
            throw SpotifyAPIError.httpError(http.statusCode, message)
        }
    }
}
