//
//  SpotifyWebAPI.swift
//  boringNotch
//
//  Titres likés et file d'attente Spotify via la Web API (l'AppleScript de Spotify ne sait faire ni l'un ni l'autre).
//  OAuth PKCE sans secret : redirection loopback http://127.0.0.1:8898/callback,
//  refresh token dans le trousseau. Endpoints /me/library (migration Spotify fév. 2026).
//

import AppKit
import Combine
import CryptoKit
import Defaults
import Network
import Security

@MainActor
final class SpotifyWebAPI: ObservableObject {
    static let shared = SpotifyWebAPI()
    static let port: NWEndpoint.Port = 8898
    static let redirectURI = "http://127.0.0.1:8898/callback"
    private static let scopes = "user-library-read user-library-modify user-read-playback-state user-read-currently-playing user-read-recently-played user-modify-playback-state"

    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?

    private var accessToken: String?
    private var expiry = Date.distantPast
    private var listener: NWListener?
    private var cancellables: Set<AnyCancellable> = []
    private var refreshTask: Task<Void, Never>?

    private init() {
        isConnected = Keychain.read() != nil
        // La file est lue en tâche de fond à chaque changement de titre : à l'ouverture du notch elle est déjà là.
        MusicManager.shared.$songTitle.dropFirst().removeDuplicates()
            .sink { [weak self] _ in self?.refresh(settle: .milliseconds(800)) }
            .store(in: &cancellables)
    }

    // MARK: - Connexion

    func connect() {
        let clientID = Defaults[.spotifyClientID].trimmingCharacters(in: .whitespaces)
        guard !clientID.isEmpty else { lastError = "Renseignez le Client ID."; return }
        lastError = nil
        let verifier = Self.randomURLSafe(64)
        let state = Self.randomURLSafe(16)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL

        startListener { [weak self] code, returnedState in
            guard let self, returnedState == state else { return }
            Task { await self.exchange(code: code, verifier: verifier, clientID: clientID) }
        }

        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: state),
            .init(name: "scope", value: Self.scopes),
        ]
        NSWorkspace.shared.open(c.url!)
    }

    func disconnect() {
        Keychain.delete()
        accessToken = nil
        isConnected = false
    }

    // MARK: - Bibliothèque

    /// nil si non connecté ou en cas d'erreur.
    func isSaved(_ uri: String) async -> Bool? {
        guard let data = await call("GET", "me/library/contains", query: [.init(name: "uris", value: uri)]),
              let arr = try? JSONDecoder().decode([Bool].self, from: data) else { return nil }
        return arr.first
    }

    /// true si la requête a abouti.
    func setSaved(_ uri: String, _ saved: Bool) async -> Bool {
        await call(saved ? "PUT" : "DELETE", "me/library", query: [.init(name: "uris", value: uri)]) != nil
    }

    // MARK: - Appareils (Spotify Connect)

    /// nil si non connecté ou en cas d'erreur.
    func devices() async -> [SpotifyDevice]? {
        guard let data = await call("GET", "me/player/devices") else { return nil }
        return SpotifyConnect.decode(data)
    }

    /// Transfère la lecture (et la relance) ; false si refusé, p. ex. jeton antérieur au scope user-modify-playback-state.
    func transfer(to deviceID: String) async -> Bool {
        let body = try? JSONSerialization.data(withJSONObject: ["device_ids": [deviceID], "play": true] as [String: Any])
        return await call("PUT", "me/player", body: body) != nil
    }

    // MARK: - File d'attente

    struct QueueTrack: Identifiable, Equatable {
        let id: String  // uri
        let title: String
        let artist: String
        let artURL: URL?
    }

    /// Titre précédent et deux suivants ; nil si non connecté, sans lecture active ou scopes manquants
    /// (connexion antérieure à la file d'attente : il faut se reconnecter).
    func upNext() async -> (previous: QueueTrack?, next: [QueueTrack])? {
        async let queueData = call("GET", "me/player/queue")
        async let recentData = call("GET", "me/player/recently-played", query: [.init(name: "limit", value: "5")])
        let (qd, rd) = await (queueData, recentData)
        guard let qd, let q = try? JSONDecoder().decode(QueueResponse.self, from: qd) else { return nil }
        let current = q.currently_playing?.uri
        var previous: QueueTrack?
        if let rd, let r = try? JSONDecoder().decode(RecentResponse.self, from: rd) {
            previous = r.items.map(\.track).first { $0.uri != current }?.queueTrack
        }
        // Spotify répète la file (lecture en boucle, playlist courte) : on dédoublonne, identifiant stable pour l'animation.
        var seen: Set<String> = [current ?? ""]
        let next = q.queue.filter { seen.insert($0.uri).inserted }.prefix(2).map(\.queueTrack)
        return (previous, Array(next))
    }

    /// Dernière file lue, gardée entre deux ouvertures du notch (affichage immédiat, relecture derrière).
    @Published private(set) var snapshot: (previous: QueueTrack?, next: [QueueTrack], devices: [SpotifyDevice])?

    /// Relit file, titre précédent et appareils en parallèle (au lieu de trois allers-retours à la suite).
    /// `settle` laisse à Spotify le temps de faire avancer sa file après un changement de titre.
    func refresh(settle: Duration = .zero) {
        refreshTask?.cancel()
        guard isConnected else { return }
        refreshTask = Task {
            if settle > .zero { try? await Task.sleep(for: settle) }
            // Testé après le délai : le titre change un cran avant le bundle quand on passe d'une app à l'autre.
            guard MusicManager.shared.bundleIdentifier == "com.spotify.client" else { snapshot = nil; return }
            async let devs = devices()
            async let queue = upNext()
            let (d, q) = await (devs, queue)
            guard !Task.isCancelled, let q else { return }
            snapshot = (q.previous, q.next, d ?? snapshot?.devices ?? [])
        }
    }

    /// Morceau ou épisode de podcast (champs optionnels pour décoder les deux).
    private struct APIItem: Decodable {
        struct Named: Decodable { let name: String }
        struct Image: Decodable { let url: URL }
        struct Album: Decodable { let images: [Image] }
        let uri: String
        let name: String
        let artists: [Named]?
        let album: Album?
        let show: Named?
        let images: [Image]?

        // Spotify trie les images de la plus grande à la plus petite (64 px) : la dernière suffit en vignette.
        var queueTrack: QueueTrack {
            QueueTrack(id: uri, title: name,
                       artist: artists?.map(\.name).joined(separator: ", ") ?? show?.name ?? "",
                       artURL: (album?.images ?? images)?.last?.url)
        }
    }
    private struct QueueResponse: Decodable { let currently_playing: APIItem?; let queue: [APIItem] }
    private struct RecentResponse: Decodable { struct Item: Decodable { let track: APIItem }; let items: [Item] }

    private func call(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, retry: Bool = true) async -> Data? {
        guard let token = await validToken() else { return nil }
        var c = URLComponents(string: "https://api.spotify.com/v1/" + path)!
        if !query.isEmpty { c.queryItems = query }
        var req = URLRequest(url: c.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let status = (resp as? HTTPURLResponse)?.statusCode else { return nil }
        if status == 401, retry {
            accessToken = nil
            return await call(method, path, query: query, body: body, retry: false)
        }
        guard (200..<300).contains(status) else {
            lastError = "Spotify \(status) : \(String(data: data, encoding: .utf8) ?? "")"
            return nil
        }
        return data
    }

    // MARK: - Jetons

    private func validToken() async -> String? {
        if let accessToken, expiry > Date().addingTimeInterval(30) { return accessToken }
        guard let refresh = Keychain.read() else { isConnected = false; return nil }
        let ok = await token([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": Defaults[.spotifyClientID],
        ])
        return ok ? accessToken : nil
    }

    private func exchange(code: String, verifier: String, clientID: String) async {
        _ = await token([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
    }

    private func token(_ form: [String: String]) async -> Bool {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents()
        c.queryItems = form.map { .init(name: $0.key, value: $0.value) }
        // ponytail: percentEncodedQuery n'encode pas « + », Spotify le lirait comme espace.
        req.httpBody = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)

        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            lastError = "Réseau indisponible."; return false
        }
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let t = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            // Refresh refusé (révoqué, Client ID changé) : on repart de zéro.
            if form["grant_type"] == "refresh_token" { disconnect() }
            lastError = "Connexion refusée : \(String(data: data, encoding: .utf8) ?? "")"
            return false
        }
        accessToken = t.access_token
        expiry = Date().addingTimeInterval(t.expires_in)
        if let r = t.refresh_token { Keychain.save(r) }
        isConnected = true
        lastError = nil
        return true
    }

    // MARK: - Redirection loopback

    private func startListener(onCode: @escaping (String, String) -> Void) {
        listener?.cancel()
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: Self.port)
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params) else { lastError = "Port 8898 indisponible."; return }
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                let line = data.flatMap { String(data: $0, encoding: .utf8) }?
                    .split(separator: "\r\n").first.map(String.init) ?? ""
                // « GET /callback?code=…&state=… HTTP/1.1 »
                let target = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let items = URLComponents(string: target)?.queryItems ?? []
                let code = items.first { $0.name == "code" }?.value
                let state = items.first { $0.name == "state" }?.value ?? ""
                let msg = code != nil ? "Boring Notch est connecté à Spotify. Vous pouvez fermer cet onglet."
                                      : "Connexion Spotify annulée."
                let html = "<html><meta charset=utf-8><body style=\"font:16px -apple-system;text-align:center;padding:60px\">\(msg)</body></html>"
                let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
                guard target.hasPrefix("/callback") else { return }
                MainActor.assumeIsolated {
                    self?.listener?.cancel()
                    self?.listener = nil
                    if let code { onCode(code, state) } else { self?.lastError = "Connexion annulée." }
                }
            }
        }
        l.start(queue: .main)
        listener = l
    }

    private static func randomURLSafe(_ bytes: Int) -> String {
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        return Data(b).base64URL
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Refresh token Spotify dans le trousseau (mot de passe générique).
private enum Keychain {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "boringNotch.spotify",
        kSecAttrAccount as String: "refresh_token",
    ]

    static func read() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func save(_ value: String) {
        delete()
        var q = base
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete() { SecItemDelete(base as CFDictionary) }
}
