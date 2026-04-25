//
//  SpotifyKeychainManager.swift
//  boringNotch
//
//  Created by Dan on 4/15/26.
//
import Foundation
import Security

class SpotifyKeychainManager {
    static let shared = SpotifyKeychainManager()
    
    private let clientSecretKey = "theboringteam.boringnotch.spotify_client_secret"
    private let accessTokenKey = "theboringteam.boringnotch.spotify_access_token"
    private let refreshTokenKey = "theboringteam.boringnotch.spotify_refresh_token"
    private let expiryKey = "theboringteam.boringnotch.spotify_token_expiry"
    
    // MARK: - Access Token
    
    var accessToken: String? {
        get { read(key: accessTokenKey) }
        set { newValue == nil ? delete(key: accessTokenKey) : save(key: accessTokenKey, value: newValue!) }
    }
    
    var refreshToken: String? {
        get { read(key: refreshTokenKey) }
        set { newValue == nil ? delete(key: refreshTokenKey) : save(key: refreshTokenKey, value: newValue!)}
    }
    
    var tokenExpiry: Date? {
        get {
            guard let str = read(key: expiryKey), let ts = Double(str) else { return nil }
            return Date(timeIntervalSince1970: ts)
        }
        set {
            guard let date = newValue else { delete(key: expiryKey); return }
            save(key: expiryKey, value: String(date.timeIntervalSince1970))
        }
    }

    var clientSecret: String? {
        get { read(key: clientSecretKey) }
        set { newValue == nil ? delete(key: clientSecretKey) : save(key: clientSecretKey, value: newValue!) }
    }
    
    var isTokenValid: Bool {
        guard accessToken != nil, let expiry = tokenExpiry else { return false }
        return Date() < expiry.addingTimeInterval(-60)
    }
    
    // MARK: - Keychain Helpers
    private func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func read(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    private func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    func clearTokens() {
        delete(key: accessTokenKey)
        delete(key: refreshTokenKey)
        delete(key: expiryKey)
    }

    func clearAll() {
        clearTokens()
        delete(key: clientSecretKey)
    }
    
}
