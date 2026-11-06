//
//  LastFMModels.swift
//  boringNotch
//
//  Created for last.fm scrobbling support.
//

import Foundation

// MARK: - Authentication

struct LastFMTokenResponse: Decodable {
    let token: String
}

struct LastFMSessionResponse: Decodable {
    let session: Session
    
    struct Session: Decodable {
        let key: String
        let name: String
    }
}

// MARK: - Errors

enum LastFMError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, message: String)
    case decodingError(Error)
    case apiError(String)
    case notAuthenticated
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL for last.fm request"
        case .httpError(let statusCode, let message):
            return "last.fm HTTP \(statusCode): \(message)"
        case .decodingError(let error):
            return "Error decoding last.fm response: \(error.localizedDescription)"
        case .apiError(let message):
            return "last.fm API error: \(message)"
        case .notAuthenticated:
            return "last.fm authentication required"
        }
    }
}

// MARK: - Scrobble Result

struct LastFMScrobbleResponse: Decodable {
    let scrobbles: Scrobbles?
    
    struct Scrobbles: Decodable {
        let accepted: String?
        let ignored: String?
    }
}

// MARK: - Scrobble Policy

/// last.fm scrobbling rule: scrobble after half the track duration or 4 minutes,
/// whichever is less. Tracks shorter than 30 seconds are never scrobbled.
enum LastFMScrobblePolicy {
    static func shouldScrobble(duration: TimeInterval, elapsed: TimeInterval) -> Bool {
        guard duration >= 30 else { return false }
        let threshold = min(duration / 2.0, 240)
        return elapsed >= threshold
    }
}
