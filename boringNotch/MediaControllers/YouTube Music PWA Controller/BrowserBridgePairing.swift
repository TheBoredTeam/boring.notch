//
//  BrowserBridgePairing.swift
//  boringNotch
//
//  The shared secret that authorises a browser extension to drive playback.
//
//  Kept apart from BrowserBridgeProtocol/BrowserBridgeServer so those two stay free of
//  any settings dependency and can be compiled and exercised on their own.
//

import Defaults
import Foundation
import Security

/// The bridge listener is bound to loopback, but loopback is still reachable by every
/// local process — including any web page the user happens to have open — so possession
/// of this token is what actually grants control.
///
/// It is minted once and then persisted. Generating it as a `Defaults` key default would
/// produce a fresh value on every launch and silently unpair a configured extension.
enum BrowserBridgePairing {
    /// The current token, creating and storing one on first use.
    static var token: String {
        let existing = Defaults[.browserBridgeToken]
        if !existing.isEmpty { return existing }
        let fresh = generateToken()
        Defaults[.browserBridgeToken] = fresh
        return fresh
    }

    /// Invalidates the old token. Any paired extension must be given the new one.
    @discardableResult
    static func regenerateToken() -> String {
        let fresh = generateToken()
        Defaults[.browserBridgeToken] = fresh
        return fresh
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // Non-cryptographic fallback; SecRandomCopyBytes failing here would be
            // extraordinary, and an unusable bridge is worse than a weaker token.
            bytes = (0..<16).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
