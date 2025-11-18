//
//  YouTubeMusicNetworking.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-14.
//

import Foundation

// MARK: - HTTP Client
final class YouTubeMusicHTTPClient: ObservableObject {
    private let session: URLSession
    private let baseURL: String
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()
    
    init(baseURL: String) {
        self.baseURL = baseURL
        
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Authentication
    func authenticate() async throws -> String {
        guard let url = URL(string: "\(baseURL)/auth/boringNotch") else {
            throw YouTubeMusicError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let authResponse: AuthResponse = try Self.decoder.decode(AuthResponse.self, from: data)
        return authResponse.accessToken
    }
    
    // MARK: - Playback Info
    func getPlaybackInfo(token: String) async throws -> PlaybackResponse {
        let data = try await sendCommand(
            endpoint: "/song",
            method: "GET",
            token: token
        )
        return try Self.decoder.decode(PlaybackResponse.self, from: data)
    }

    // MARK: - Like / Favourites
    struct LikeStateResponse: Decodable, Sendable {
        let state: String?
    }


    func getLikeState(token: String) async throws -> LikeStateResponse {
        let data = try await sendCommand(endpoint: "/like-state", method: "GET", token: token)
        return try Self.decoder.decode(LikeStateResponse.self, from: data)
    }

    func toggleLike(token: String) async throws -> Data {
        return try await sendCommand(endpoint: "/like", method: "POST", token: token)
    }

    func toggleDislike(token: String) async throws -> Data {
        return try await sendCommand(endpoint: "/dislike", method: "POST", token: token)
    }
    
    // MARK: - Commands
    func sendCommand(
        endpoint: String,
        method: String = "POST",
        body: (any Codable & Sendable)? = nil,
        token: String
    ) async throws -> Data {
        let request = try createAuthenticatedRequest(
            endpoint: "/api/v1\(endpoint)",
            method: method,
            body: body,
            token: token
        )
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return data
    }
    
    // MARK: - Private Helpers
    private func createAuthenticatedRequest(
        endpoint: String,
        method: String,
        body: (any Codable & Sendable)? = nil,
        token: String
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw YouTubeMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            request.httpBody = try Self.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        return request
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeMusicError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw YouTubeMusicError.authenticationRequired
        default:
            throw YouTubeMusicError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - WebSocket Client
actor YouTubeMusicWebSocketClient {
    private var task: URLSessionWebSocketTask?
    private let session: URLSession
    private let onMessage: @Sendable (Data) async -> Void
    private let onDisconnect: @Sendable () async -> Void
    
    var isConnected: Bool { task != nil }
    
    init(
        onMessage: @escaping @Sendable (Data) async -> Void,
        onDisconnect: @escaping @Sendable () async -> Void,
        session: URLSession = .shared
    ) {
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
        self.session = session
    }
    
    func connect(to url: URL, with token: String) async throws {
        await disconnect()
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let newTask = session.webSocketTask(with: request)
        task = newTask
        newTask.resume()
        
        Task { await listenForMessages() }
    }
    
    func disconnect() async {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
    
    private func listenForMessages() async {
        guard let currentTask = task else { return }
        
        while !Task.isCancelled && task != nil {
            do {
                let message = try await currentTask.receive()
                
                let data: Data
                switch message {
                case .data(let d):
                    data = d
                case .string(let s):
                    data = s.data(using: .utf8) ?? Data()
                @unknown default:
                    continue
                }
                
                await onMessage(data)
            } catch {
                break
            }
        }
        task = nil
        await onDisconnect()
    }
}

// MARK: - WebSocket URL Helper
struct WebSocketURLBuilder {
    static func buildURL(from baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }

        switch components.scheme {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        default:
            break
        }

        components.path = "/api/v1/ws"
        return components.url
    }
}

// MARK: - Errors
enum YouTubeMusicError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case authenticationRequired
    case webSocketNotConnected
    case encodingFailed
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .authenticationRequired:
            return "Authentication required"
        case .webSocketNotConnected:
            return "WebSocket not connected"
        case .encodingFailed:
            return "Failed to encode data"
        case .decodingFailed:
            return "Failed to decode data"
        }
    }
}
