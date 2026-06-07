import AppKit
import Foundation
import SpotifyAdDampenerCore

@MainActor
final class SpotifyAuthService: ObservableObject {
    enum AuthState: Equatable {
        case notConfigured
        case signedOut
        case authorizing
        case signedIn
        case error(String)
    }

    @Published private(set) var state: AuthState

    private let configuration: SpotifyAuthConfiguration
    private let tokenStore: KeychainTokenStore
    private let session: URLSession
    private var pendingVerifier: String?
    private var pendingState: String?

    init(configuration: SpotifyAuthConfiguration = .current(), tokenStore: KeychainTokenStore = KeychainTokenStore(), session: URLSession = .shared) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.session = session
        if !configuration.isConfigured {
            self.state = .notConfigured
        } else if (try? tokenStore.loadToken()) != nil {
            self.state = .signedIn
        } else {
            self.state = .signedOut
        }
    }

    var isConfigured: Bool { configuration.isConfigured }

    func connect() {
        guard configuration.isConfigured else { state = .notConfigured; return }
        do {
            let pair = try PKCE.pair()
            let stateToken = UUID().uuidString
            pendingVerifier = pair.verifier
            pendingState = stateToken
            let url = try PKCE.authorizationURL(
                clientID: configuration.clientID,
                redirectURI: SpotifyAuthConfiguration.redirectURI,
                scopes: SpotifyAuthConfiguration.scopes,
                state: stateToken,
                codeChallenge: pair.challenge
            )
            state = .authorizing
            NSWorkspace.shared.open(url)
        } catch {
            state = .error("Could not start Spotify authorization.")
        }
    }

    func handleCallbackURL(_ url: URL) {
        guard url.scheme == SpotifyAuthConfiguration.callbackScheme,
              url.host == SpotifyAuthConfiguration.callbackHost,
              url.path == SpotifyAuthConfiguration.callbackPath else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if components?.queryItems?.first(where: { $0.name == "error" })?.value != nil {
            state = .error("Spotify authorization was cancelled or denied.")
            return
        }
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = components?.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == pendingState,
              let verifier = pendingVerifier else {
            state = .error("Spotify authorization callback was invalid.")
            return
        }
        Task { await exchangeCode(code, verifier: verifier) }
    }

    func validAccessToken() async throws -> String {
        guard let token = try tokenStore.loadToken() else {
            await MainActor.run { self.state = self.configuration.isConfigured ? .signedOut : .notConfigured }
            throw URLError(.userAuthenticationRequired)
        }
        if !token.isExpired {
            await MainActor.run { self.state = .signedIn }
            return token.accessToken
        }
        return try await refreshAccessToken(token)
    }

    func refreshAfterUnauthorized() async throws -> String {
        guard let token = try tokenStore.loadToken(), token.refreshToken != nil else {
            await MainActor.run { self.state = .signedOut }
            throw URLError(.userAuthenticationRequired)
        }
        return try await refreshAccessToken(token)
    }

    func disconnect() {
        try? tokenStore.deleteToken()
        pendingVerifier = nil
        pendingState = nil
        state = configuration.isConfigured ? .signedOut : .notConfigured
    }

    private func exchangeCode(_ code: String, verifier: String) async {
        do {
            let token = try await requestToken(parameters: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": SpotifyAuthConfiguration.redirectURI,
                "client_id": configuration.clientID,
                "code_verifier": verifier
            ], previousRefreshToken: nil)
            try tokenStore.saveToken(token)
            pendingVerifier = nil
            pendingState = nil
            state = .signedIn
            SpotifyAdDampenerManager.shared.startIfNeeded()
        } catch {
            state = .error("Spotify token exchange failed.")
        }
    }

    private func refreshAccessToken(_ token: SpotifyAuthToken) async throws -> String {
        guard let refreshToken = token.refreshToken else { throw URLError(.userAuthenticationRequired) }
        let refreshed = try await requestToken(parameters: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": configuration.clientID
        ], previousRefreshToken: refreshToken)
        try tokenStore.saveToken(refreshed)
        await MainActor.run { self.state = .signedIn }
        return refreshed.accessToken
    }

    private func requestToken(parameters: [String: String], previousRefreshToken: String?) async throws -> SpotifyAuthToken {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.map { key, value in
            "\(urlEncode(key))=\(urlEncode(value))"
        }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        return decoded.authToken(previousRefreshToken: previousRefreshToken)
    }

    private func urlEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }
}
