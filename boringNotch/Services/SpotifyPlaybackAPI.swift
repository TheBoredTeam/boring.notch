import Foundation
import SpotifyAdDampenerCore

final class SpotifyPlaybackAPI {
    enum PlaybackResult: Equatable {
        case snapshot(SpotifyPlaybackSnapshot)
        case authRequired
        case networkFailed
    }

    private let authService: SpotifyAuthService
    private let session: URLSession

    init(authService: SpotifyAuthService, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
    }

    func currentlyPlaying() async -> PlaybackResult {
        do {
            let token = try await authService.validAccessToken()
            return try await requestCurrentlyPlaying(accessToken: token, allowRefresh: true)
        } catch {
            return .authRequired
        }
    }

    private func requestCurrentlyPlaying(accessToken: String, allowRefresh: Bool) async throws -> PlaybackResult {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .networkFailed }
            if http.statusCode == 401 {
                guard allowRefresh else { return .authRequired }
                do {
                    let refreshed = try await authService.refreshAfterUnauthorized()
                    return try await requestCurrentlyPlaying(accessToken: refreshed, allowRefresh: false)
                } catch {
                    return .authRequired
                }
            }
            guard (200..<300).contains(http.statusCode) || http.statusCode == 204 else { return .networkFailed }
            return .snapshot(try SpotifyPlaybackParser.parse(statusCode: http.statusCode, data: data))
        } catch is DecodingError {
            return .networkFailed
        } catch {
            return .networkFailed
        }
    }
}
