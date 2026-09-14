//
//  YouTubeMusicAuthentication.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-14.
//

import Foundation

// MARK: - Authentication Manager
actor YouTubeMusicAuthManager {
    private struct Attempt {
        let id = UUID()
        let task: Task<String, Error>
    }

    private var accessToken: String?
    private var attempt: Attempt?
    private var generation: UInt64 = 0
    private let requestAuthentication: @Sendable () async throws -> String

    init(httpClient: YouTubeMusicHTTPClient) {
        requestAuthentication = { try await httpClient.authenticate() }
    }

    init(requestAuthentication: @escaping @Sendable () async throws -> String) {
        self.requestAuthentication = requestAuthentication
    }

    var currentToken: String? { accessToken }

    func authenticate() async throws -> String {
        try Task.checkCancellation()
        if let token = accessToken { return token }
        let expectedGeneration = generation
        let active: Attempt
        if let attempt {
            active = attempt
        } else {
            let request = requestAuthentication
            active = Attempt(task: Task { try await request() })
            attempt = active
        }

        do {
            let token = try await active.task.value
            guard generation == expectedGeneration else { throw CancellationError() }
            guard !token.isEmpty else { throw YouTubeMusicError.authenticationRequired }
            if attempt?.id == active.id {
                accessToken = token
                attempt = nil
            }
            try Task.checkCancellation()
            return token
        } catch {
            // Another caller may already have started a replacement attempt.
            if attempt?.id == active.id { attempt = nil }
            throw error
        }
    }

    func invalidateToken() {
        generation &+= 1
        accessToken = nil
        attempt?.task.cancel()
        attempt = nil
    }
}

// MARK: - Authentication State
enum AuthenticationState: Sendable {
    case unauthenticated
    case authenticating
    case authenticated(String)
    case failed(Error)
    
    var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }
    
    var token: String? {
        if case .authenticated(let token) = self {
            return token
        }
        return nil
    }
}