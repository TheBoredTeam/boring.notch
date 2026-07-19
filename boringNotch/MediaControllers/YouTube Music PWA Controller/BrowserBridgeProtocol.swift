//
//  BrowserBridgeProtocol.swift
//  boringNotch
//
//  Wire format spoken between Boring Notch and the browser extension that bridges
//  the YouTube Music web player. Both ends must agree on `browserBridgeProtocolVersion`.
//

import Defaults
import Foundation
import Security

/// Bumped only on a breaking change to the message shapes below.
let browserBridgeProtocolVersion = 1

// MARK: - Configuration

struct BrowserBridgeConfiguration: Sendable {
    let port: UInt16
    /// A client that stops sending keepalives is treated as gone.
    let clientTimeout: TimeInterval

    static let defaultPort: UInt16 = 26539

    static let `default` = BrowserBridgeConfiguration(
        port: defaultPort,
        clientTimeout: 45
    )
}

// MARK: - Pairing

/// The shared secret that authorises a browser extension.
///
/// The listener is bound to loopback, but loopback is still reachable by any local
/// process — including any web page the user has open — so possession of this token is
/// what actually grants control. It is minted once and then persisted, because
/// regenerating it would silently unpair an already-configured extension.
enum BrowserBridgePairing {
    static var token: String {
        let existing = Defaults[.browserBridgeToken]
        if !existing.isEmpty { return existing }
        let fresh = generateToken()
        Defaults[.browserBridgeToken] = fresh
        return fresh
    }

    @discardableResult
    static func regenerateToken() -> String {
        let fresh = generateToken()
        Defaults[.browserBridgeToken] = fresh
        return fresh
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<16).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Extension -> App

enum BrowserBridgeInboundType: String, Decodable, Sendable {
    case hello
    case state
    case ping
    case bye
}

/// Playback snapshot as the extension observes it in the page.
///
/// Everything except `isPlaying` is optional: the extension omits fields the page
/// hasn't populated yet rather than inventing values, so a missing field means
/// "unchanged", not "zero".
struct BrowserBridgeTrackState: Decodable, Sendable {
    let hasTrack: Bool?
    let isPlaying: Bool
    let title: String?
    let artist: String?
    let album: String?
    let artworkUrl: String?
    /// Seconds.
    let duration: Double?
    /// Seconds.
    let position: Double?
    /// Normalised 0...1.
    let volume: Double?
    let isMuted: Bool?
    /// "off", "one" or "all".
    let repeatMode: String?
    let isFavorite: Bool?
}

struct BrowserBridgeInboundMessage: Decodable, Sendable {
    let v: Int?
    let type: BrowserBridgeInboundType
    let token: String?
    let client: String?
    let extensionId: String?
    let extensionVersion: String?
    let source: String?
    let state: BrowserBridgeTrackState?
}

// MARK: - App -> Extension

enum BrowserBridgeCommand: String, Encodable, Sendable {
    case play
    case pause
    case toggle
    case next
    case previous
    case seek
    case setVolume
    case toggleShuffle
    case toggleRepeat
    case setFavorite
}

struct BrowserBridgeOutboundMessage: Encodable, Sendable {
    let v: Int
    let type: String
    var action: BrowserBridgeCommand?
    var value: Double?
    var reason: String?
    var app: String?

    static func welcome() -> BrowserBridgeOutboundMessage {
        BrowserBridgeOutboundMessage(
            v: browserBridgeProtocolVersion, type: "welcome", app: "BoringNotch"
        )
    }

    static func pong() -> BrowserBridgeOutboundMessage {
        BrowserBridgeOutboundMessage(v: browserBridgeProtocolVersion, type: "pong")
    }

    static func error(_ reason: String) -> BrowserBridgeOutboundMessage {
        BrowserBridgeOutboundMessage(
            v: browserBridgeProtocolVersion, type: "error", reason: reason
        )
    }

    static func command(_ action: BrowserBridgeCommand, value: Double? = nil) -> BrowserBridgeOutboundMessage {
        BrowserBridgeOutboundMessage(
            v: browserBridgeProtocolVersion, type: "command", action: action, value: value
        )
    }
}

// MARK: - Errors

enum BrowserBridgeError: Error, LocalizedError, Sendable {
    case listenerFailed(String)
    case portUnavailable(UInt16)
    case notRunning
    case noClient
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .listenerFailed(let detail):
            return "The browser bridge could not start: \(detail)"
        case .portUnavailable(let port):
            return "Port \(port) is already in use. Choose a different port in Settings."
        case .notRunning:
            return "The browser bridge is not running."
        case .noClient:
            return "No browser extension is connected."
        case .encodingFailed:
            return "Failed to encode a bridge message."
        }
    }
}
