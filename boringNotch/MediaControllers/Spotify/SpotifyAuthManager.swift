//
//  SpotifyAuthManager.swift
//  boringNotch
//
//  Created by Dan on 4/15/26.
//
import Foundation
import AppKit
import Defaults

@MainActor
final class SpotifyAuthManager: ObservableObject {
    static let shared = SpotifyAuthManager()
    
    // MARK: - Config
    private let redirectURI = "theboringteam.boringnotch://spotify-callback"
    private let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-library-read",
        "user-library-modify"
    ]
    
    private let keychain = SpotifyKeychainManager.shared
    @Published var isAuthorized = false
    
    init() {
        isAuthorized = keychain.isTokenValid || keychain.refreshToken != nil
    }

    var hasConfiguredCredentials: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty
    }
    
    func startAuthFlow() {
        guard hasConfiguredCredentials else {
            return
        }

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id",     value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri",  value: redirectURI),
            .init(name: "scope",         value: scopes.joined(separator: " ")),
            .init(name: "show_dialog",   value: "true")
        ]
        NSWorkspace.shared.open(components.url!)
    }
    
    func handleCallback(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            return
        }
        
        await exchangeCode(code)
    }
        
    // MARK: - Exchange Code
    
    private func exchangeCode(_ code: String) async {
        guard hasConfiguredCredentials else {
            return
        }

        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(basicAuthHeader)", forHTTPHeaderField: "Authorization")
        
        let body = [
            "grant_type":   "authorization_code",
            "code":         code,
            "redirect_uri": redirectURI
        ]
        request.httpBody = body.urlEncoded
        
        await performTokenRequest(request)
    }
        
    // MARK: - Refresh Token
    
    func refreshTokenIfNeeded() async {
        guard !keychain.isTokenValid else { return }
        guard hasConfiguredCredentials else {
            isAuthorized = false
            return
        }
        guard let refreshToken = keychain.refreshToken else {
            isAuthorized = false
            return
        }
        
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(basicAuthHeader)", forHTTPHeaderField: "Authorization")
        
        let body = [
            "grant_type":    "refresh_token",
            "refresh_token": refreshToken
        ]
        request.httpBody = body.urlEncoded
        
        await performTokenRequest(request)
    }
        
    // MARK: - Token Request Handler
    
    private func performTokenRequest(_ request: URLRequest) async {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse else {
            return
        }
        
        guard let json = try? JSONDecoder().decode(SpotifyTokenResponse.self, from: data) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            return
        }
        
        keychain.accessToken  = json.accessToken
        keychain.tokenExpiry  = Date().addingTimeInterval(TimeInterval(json.expiresIn))
        if let refresh = json.refreshToken {
            keychain.refreshToken = refresh
        }

        isAuthorized = true
        NotificationCenter.default.post(name: .spotifyAuthorizationChanged, object: nil)
    }
        
    // MARK: - Valid Token (auto-refreshes)
    
    func validToken() async -> String? {
        await refreshTokenIfNeeded()
        let token = keychain.accessToken
        return token
    }
        
    // MARK: - Sign Out
    
    func signOut() {
        keychain.clearTokens()
        isAuthorized = false
        NotificationCenter.default.post(name: .spotifyAuthorizationChanged, object: nil)
    }

    func handleCredentialChange() {
        if isAuthorized {
            signOut()
        }
    }
    
    // MARK: - Helpers

    private var clientID: String {
        Defaults[.spotifyClientID].trimmedSpotifyCredential
    }

    private var clientSecret: String {
        keychain.clientSecret?.trimmedSpotifyCredential ?? ""
    }

    func storedClientSecret() -> String {
        clientSecret
    }

    func updateClientSecret(_ secret: String) {
        let trimmedSecret = secret.trimmedSpotifyCredential
        let currentSecret = clientSecret
        guard trimmedSecret != currentSecret else { return }

        keychain.clientSecret = trimmedSecret.isEmpty ? nil : trimmedSecret
        handleCredentialChange()
    }
    
    private var basicAuthHeader: String {
        let credentials = "\(clientID):\(clientSecret)"
        return Data(credentials.utf8).base64EncodedString()
    }
}

// MARK: - Token Response

private struct SpotifyTokenResponse: Decodable {
    let accessToken:  String
    let expiresIn:    Int
    let refreshToken: String?
    let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case expiresIn    = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

// MARK: - Helpers

private extension Dictionary where Key == String, Value == String {
    var urlEncoded: Data? {
        map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
    }
}

private extension String {
    var trimmedSpotifyCredential: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
