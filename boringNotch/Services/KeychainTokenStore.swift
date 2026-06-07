import Foundation
import Security

final class KeychainTokenStore {
    enum StoreError: Error { case unexpectedStatus(OSStatus) }

    private let service = "theboringteam.boringnotch.spotify-ad-dampener"
    private let account = "spotify-oauth-token"

    func loadToken() throws -> SpotifyAuthToken? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
        guard let data = item as? Data else { return nil }
        return try JSONDecoder().decode(SpotifyAuthToken.self, from: data)
    }

    func saveToken(_ token: SpotifyAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound { throw StoreError.unexpectedStatus(updateStatus) }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw StoreError.unexpectedStatus(addStatus) }
    }

    func deleteToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.unexpectedStatus(status) }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
