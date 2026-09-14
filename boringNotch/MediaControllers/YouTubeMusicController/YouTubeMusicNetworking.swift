//
//  YouTubeMusicNetworking.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-14.
//

import Foundation
import os
import Combine

// MARK: - HTTP Client
final class YouTubeMusicHTTPClient: Sendable {
    private let session: URLSession
    private let baseURL: String
    private let retired = OSAllocatedUnfairLock(initialState: false)
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()
    
    init(baseURL: String, session: URLSession? = nil) {
        self.baseURL = baseURL
        
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        
        self.session = session ?? URLSession(configuration: config)
    }
    
    deinit { session.invalidateAndCancel() }

    func cancelAllRequests() {
        retired.withLock { $0 = true }
        // Async callers may already be entering URLSession. Invalidating it here
        // can raise an Objective-C exception while such a caller creates a task.
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        guard !retired.withLock({ $0 }) else { throw CancellationError() }
        return try await session.data(for: request)
    }

    // MARK: - Authentication
    func authenticate() async throws -> String {
        guard let url = URL(string: "\(baseURL)/auth/boringNotch") else {
            throw YouTubeMusicError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await data(for: request)
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
        
        let (data, response) = try await data(for: request)
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
protocol YouTubeMusicWebSocketConnecting: AnyObject, Sendable {
    func connect(to url: URL, with token: String) async throws
    func disconnect() async
}

enum PearDisconnectReason: Sendable {
    case unauthorized
    case transient

    static func classify(closeCode: URLSessionWebSocketTask.CloseCode, response: URLResponse?) -> Self {
        let status = (response as? HTTPURLResponse)?.statusCode
        return closeCode == .policyViolation || status == 401 || status == 403 ? .unauthorized : .transient
    }
}

actor YouTubeMusicWebSocketClient: YouTubeMusicWebSocketConnecting {
    private final class ConnectionState {
        let task: URLSessionWebSocketTask
        var suppressDisconnectCallback = false

        init(task: URLSessionWebSocketTask) {
            self.task = task
        }
    }

    private var connection: ConnectionState?
    private let session: URLSession
    private let onMessage: @Sendable (Data) async -> Void
    private let onDisconnect: @Sendable (PearDisconnectReason) async -> Void
    
    var isConnected: Bool { connection != nil }
    
    init(
        onMessage: @escaping @Sendable (Data) async -> Void,
        onDisconnect: @escaping @Sendable (PearDisconnectReason) async -> Void,
        session: URLSession = .shared
    ) {
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
        self.session = session
    }
    
    func connect(to url: URL, with token: String) throws {
        let request = try WebSocketURLBuilder.authenticatedRequest(to: url, token: token)
        disconnect()
        
        let newTask = session.webSocketTask(with: request)
        let state = ConnectionState(task: newTask)
        connection = state
        newTask.resume()
        
        Task { await listenForMessages(for: state) }
    }
    
    func disconnect() {
        guard let currentConnection = connection else { return }
        
        currentConnection.suppressDisconnectCallback = true
        currentConnection.task.cancel(with: .goingAway, reason: nil)
        if connection === currentConnection {
            connection = nil
        }
    }
    
    private func listenForMessages(for state: ConnectionState) async {
        guard connection === state else { return }
        
        while !Task.isCancelled && connection === state {
            do {
                let message = try await state.task.receive()
                guard connection === state, !state.suppressDisconnectCallback else { return }
                
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
        
        guard connection === state, !state.suppressDisconnectCallback else { return }
        connection = nil
        await onDisconnect(.classify(closeCode: state.task.closeCode, response: state.task.response))
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

    /// Pear authenticates its WebSocket using the query token. Build it with
    /// URLComponents so reserved token characters cannot change the query.
    static func authenticatedRequest(to url: URL, token: String) throws -> URLRequest {
        guard !token.isEmpty else { throw YouTubeMusicError.authenticationRequired }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "ws" || components.scheme == "wss",
              let host = components.host, !host.isEmpty
        else {
            throw YouTubeMusicError.invalidURL
        }

        var items = components.queryItems ?? []
        items.removeAll { $0.name == "token" }
        items.append(URLQueryItem(name: "token", value: token))
        components.queryItems = items
        // URLSearchParams uses form decoding, where an unescaped + means space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let authenticatedURL = components.url else { throw YouTubeMusicError.invalidURL }

        var request = URLRequest(url: authenticatedURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
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
