//
//  SpotifyAuthManager.swift
//  boringNotch
//

import AppKit
import CryptoKit
import Foundation
import Network
import Security

actor SpotifyAuthManager {
    static let shared = SpotifyAuthManager()

    private let session: URLSession
    private static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    private static let randomCharacters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var pendingCodeVerifier: String?
    private var pendingState: String?
    private var callbackServer: SpotifyLoopbackCallbackServer?

    init(session: URLSession = .shared) {
        self.session = session
    }

    var isAuthenticated: Bool {
        if refreshToken != nil { return true }
        if let accessToken, let expiry = tokenExpiry, !accessToken.isEmpty, expiry > Date() {
            return true
        }
        return false
    }

    func currentAccessToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(60) {
            return token
        }
        if let refreshToken {
            try await refreshAccessToken(refreshToken: refreshToken)
            if let token = accessToken {
                return token
            }
        }
        throw SpotifyAPIError.notAuthenticated
    }

    func beginAuthorization() async throws {
        guard SpotifyConfig.isConfigured else {
            throw SpotifyAPIError.notConfigured
        }

        let verifier = Self.generateCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.generateRandomString(length: 16)

        pendingCodeVerifier = verifier
        pendingState = state

        let server = SpotifyLoopbackCallbackServer(port: SpotifyConfig.loopbackRedirectPort)
        callbackServer = server
        do {
            try await server.start()

            let redirectURI = SpotifyConfig.loopbackRedirectURI
            let authURL = try Self.makeAuthorizationURL(
                clientID: SpotifyConfig.clientID,
                redirectURI: redirectURI,
                codeChallenge: challenge,
                state: state
            )

            await MainActor.run {
                NSWorkspace.shared.open(authURL)
            }

            let callbackURL = try await server.waitForCallback()
            try await handleCallback(url: callbackURL, redirectURI: redirectURI)
            callbackServer = nil
        } catch {
            server.stop()
            callbackServer = nil
            pendingCodeVerifier = nil
            pendingState = nil
            throw error
        }
    }

    func disconnect() {
        invalidateSession()
        pendingCodeVerifier = nil
        pendingState = nil
    }

    private func invalidateSession() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
    }

    private func handleCallback(url: URL, redirectURI: String) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SpotifyAPIError.invalidResponse
        }

        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            throw SpotifyAPIError.httpError(400, error)
        }

        guard
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
            returnedState == pendingState,
            let verifier = pendingCodeVerifier
        else {
            throw SpotifyAPIError.invalidResponse
        }

        pendingCodeVerifier = nil
        pendingState = nil

        try await exchangeCode(code, verifier: verifier, redirectURI: redirectURI)
    }

    private func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = Self.formEncodedBody([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("client_id", SpotifyConfig.clientID),
            ("code_verifier", verifier),
        ])
        guard request.httpBody != nil else {
            throw SpotifyAPIError.invalidURL
        }

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)
        let token = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        storeTokens(token)
    }

    private func refreshAccessToken(refreshToken: String) async throws {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = Self.formEncodedBody([
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", SpotifyConfig.clientID),
        ])
        guard request.httpBody != nil else {
            throw SpotifyAPIError.invalidURL
        }

        let (data, response) = try await session.data(for: request)
        do {
            try validateHTTP(response: response, data: data)
        } catch {
            if isInvalidGrant(response: response, data: data) {
                invalidateSession()
            }
            throw error
        }
        let token = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        storeTokens(token, preserveRefreshToken: true)
    }

    private func isInvalidGrant(response: URLResponse, data: Data) -> Bool {
        guard let http = response as? HTTPURLResponse, http.statusCode == 400 else { return false }
        guard let body = String(data: data, encoding: .utf8) else { return false }
        return body.contains("invalid_grant")
    }

    private func storeTokens(_ token: SpotifyTokenResponse, preserveRefreshToken: Bool = false) {
        accessToken = token.accessToken
        if let refresh = token.refreshToken {
            refreshToken = refresh
        } else if !preserveRefreshToken {
            refreshToken = nil
        }
        tokenExpiry = Date().addingTimeInterval(TimeInterval(token.expiresIn))
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw SpotifyAPIError.httpError(http.statusCode, message)
        }
    }

    private static func makeAuthorizationURL(
        clientID: String,
        redirectURI: String,
        codeChallenge: String,
        state: String
    ) throws -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: SpotifyConfig.authorizationScopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else {
            throw SpotifyAPIError.invalidURL
        }
        return url
    }

    private static func generateCodeVerifier() -> String {
        generateRandomString(length: 64)
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func generateRandomString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return String((0..<length).map { _ in randomCharacters.randomElement() ?? "a" })
        }

        return String(bytes.map { randomCharacters[Int($0) % randomCharacters.count] })
    }

    private static func formEncodedBody(_ values: [(String, String)]) -> Data? {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}

private final class SpotifyLoopbackCallbackServer: @unchecked Sendable {
    private let port: UInt16
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?
    private var hasResumedPort = false

    init(port: UInt16) {
        self.port = port
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (portContinuation: CheckedContinuation<Void, Error>) in
            do {
                guard let callbackPort = NWEndpoint.Port(rawValue: port) else {
                    portContinuation.resume(throwing: SpotifyAPIError.invalidURL)
                    return
                }

                let listener = try NWListener(using: .tcp, on: callbackPort)
                self.listener = listener

                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard !self.hasResumedPort else { return }
                        self.hasResumedPort = true
                        portContinuation.resume()
                    case .failed(let error):
                        if !self.hasResumedPort {
                            self.hasResumedPort = true
                            portContinuation.resume(throwing: error)
                        } else {
                            self.continuation?.resume(throwing: error)
                            self.continuation = nil
                        }
                    default:
                        break
                    }
                }

                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection: connection)
                }

                listener.start(queue: .global(qos: .userInitiated))
            } catch {
                portContinuation.resume(throwing: error)
            }
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        if let continuation {
            self.continuation = nil
            continuation.resume(throwing: SpotifyAPIError.invalidResponse)
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }

            let firstLine = request.split(separator: "\r\n").first ?? ""
            let parts = firstLine.split(separator: " ")
            if parts.count >= 2, parts[0] == "GET" {
                let target = String(parts[1])
                if target.hasPrefix("/callback"), let url = URL(string: "http://127.0.0.1\(target)") {
                    self.respondAndFinish(connection: connection, callbackURL: url)
                    return
                }
            }

            self.respondAndFinish(
                connection: connection,
                callbackURL: nil,
                status: "400 Bad Request",
                body: "Invalid callback"
            )
        }
    }

    private func respondAndFinish(
        connection: NWConnection,
        callbackURL: URL?,
        status: String = "200 OK",
        body: String = "You can close this window and return to Boring Notch."
    ) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Connection: close\r
        \r
        <html><body><p>\(body)</p></body></html>
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
        listener?.cancel()
        listener = nil

        if let callbackURL, let continuation {
            self.continuation = nil
            continuation.resume(returning: callbackURL)
        } else if let continuation {
            self.continuation = nil
            continuation.resume(throwing: SpotifyAPIError.invalidResponse)
        }
    }
}
