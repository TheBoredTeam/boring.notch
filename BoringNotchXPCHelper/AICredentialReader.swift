//
//  AICredentialReader.swift
//  BoringNotchXPCHelper
//

import Foundation
import Security

enum AICredentialReader {
    static func readClaudeCredentials() -> (accessToken: String?, status: String, message: String?) {
        var diagLog: [String] = []

        let keychainResult = readKeychainPassword(service: "Claude Code-credentials", diag: &diagLog)
        if let keychain = keychainResult {
            return parseClaudeCredentialsJSON(keychain)
        }

        let credentialsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent(".credentials.json")

        diagLog.append("file:\(credentialsURL.path)")
        guard FileManager.default.fileExists(atPath: credentialsURL.path) else {
            diagLog.append("file:not_found")
            return (nil, CredentialStatusValue.notFound.rawValue, "diag: \(diagLog.joined(separator: "; "))")
        }

        do {
            let content = try String(contentsOf: credentialsURL, encoding: .utf8)
            return parseClaudeCredentialsJSON(content)
        } catch {
            return (nil, CredentialStatusValue.parseError.rawValue, "Failed to read Claude credentials: \(error.localizedDescription)")
        }
    }

    static func readCodexCredentials() -> (accessToken: String?, accountId: String?, status: String, message: String?) {
        var diagLog: [String] = []
        if let keychain = readKeychainPassword(service: "Codex Auth", diag: &diagLog) {
            return parseCodexCredentialsJSON(keychain)
        }

        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("auth.json")

        guard FileManager.default.fileExists(atPath: authURL.path) else {
            return (nil, nil, CredentialStatusValue.notFound.rawValue, nil)
        }

        do {
            let content = try String(contentsOf: authURL, encoding: .utf8)
            return parseCodexCredentialsJSON(content)
        } catch {
            return (nil, nil, CredentialStatusValue.parseError.rawValue, "Failed to read Codex auth: \(error.localizedDescription)")
        }
    }

    private static func readKeychainPassword(service: String, diag: inout [String]) -> String? {
        // Allow the system to show a Keychain access prompt if needed
        SecKeychainSetUserInteractionAllowed(true)

        // Approach 1: SecKeychainFindGenericPassword with explicit login keychain
        let keychainPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Keychains/login.keychain-db").path

        var loginKeychain: SecKeychain?
        let openStatus = SecKeychainOpen(keychainPath, &loginKeychain)
        diag.append("kc_open:\(openStatus)")

        if openStatus == errSecSuccess, let keychain = loginKeychain {
            var passwordLength: UInt32 = 0
            var passwordData: UnsafeMutableRawPointer?
            let findStatus = SecKeychainFindGenericPassword(
                keychain,
                UInt32(service.utf8.count), service,
                0, nil,
                &passwordLength, &passwordData,
                nil
            )
            diag.append("kc_find:\(findStatus)")

            if findStatus == errSecSuccess, let data = passwordData {
                let value = String(
                    bytesNoCopy: data,
                    length: Int(passwordLength),
                    encoding: .utf8,
                    freeWhenDone: false
                )?.trimmingCharacters(in: .whitespacesAndNewlines)
                SecKeychainItemFreeContent(nil, data)
                if let value, !value.isEmpty { return value }
            }
        }

        // Approach 2: SecItemCopyMatching default search list
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        diag.append("si_copy:\(status)")

        if status == errSecSuccess, let data = result as? Data {
            let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty { return value }
        }

        return nil
    }

    private static func parseClaudeCredentialsJSON(_ content: String) -> (accessToken: String?, status: String, message: String?) {
        guard
            let data = content.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (nil, CredentialStatusValue.parseError.rawValue, "Failed to parse Claude credentials JSON")
        }

        guard let oauth = object["claudeAiOauth"] as? [String: Any]
            ?? object["claude.ai_oauth"] as? [String: Any]
        else {
            return (nil, CredentialStatusValue.parseError.rawValue, "No Claude OAuth entry found")
        }

        guard let accessToken = oauth["accessToken"] as? String, !accessToken.isEmpty else {
            return (nil, CredentialStatusValue.parseError.rawValue, "Claude accessToken is missing")
        }

        if let expiresAt = oauth["expiresAt"], isExpired(expiresAt) {
            return (accessToken, CredentialStatusValue.expired.rawValue, "Claude OAuth token has expired")
        }

        return (accessToken, CredentialStatusValue.valid.rawValue, nil)
    }

    private static func parseCodexCredentialsJSON(_ content: String) -> (accessToken: String?, accountId: String?, status: String, message: String?) {
        guard
            let data = content.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (nil, nil, CredentialStatusValue.parseError.rawValue, "Failed to parse Codex auth JSON")
        }

        guard object["auth_mode"] as? String == "chatgpt" else {
            return (nil, nil, CredentialStatusValue.notFound.rawValue, "Codex is not using ChatGPT OAuth mode")
        }

        guard let tokens = object["tokens"] as? [String: Any] else {
            return (nil, nil, CredentialStatusValue.parseError.rawValue, "No Codex tokens found")
        }

        guard let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty else {
            return (nil, nil, CredentialStatusValue.parseError.rawValue, "Codex access_token is missing")
        }

        let accountId = tokens["account_id"] as? String
        if let lastRefresh = object["last_refresh"] as? String, isCodexTokenStale(lastRefresh) {
            return (accessToken, accountId, CredentialStatusValue.expired.rawValue, "Codex token may be stale")
        }

        return (accessToken, accountId, CredentialStatusValue.valid.rawValue, nil)
    }

    private static func isExpired(_ value: Any) -> Bool {
        let now = Date()

        if let number = value as? NSNumber {
            let raw = number.doubleValue
            let seconds = raw > 1_000_000_000_000 ? raw / 1_000 : raw
            return Date(timeIntervalSince1970: seconds) < now
        }

        if let string = value as? String, let date = parseDate(string) {
            return date < now
        }

        return false
    }

    private static func isCodexTokenStale(_ lastRefresh: String) -> Bool {
        guard let date = parseDate(lastRefresh) else { return false }
        return Date().timeIntervalSince(date) > 8 * 24 * 60 * 60
    }

    private static func parseDate(_ string: String) -> Date? {
        if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: string) {
            return date
        }
        return ISO8601DateFormatter.standard.date(from: string)
    }
}

private enum CredentialStatusValue: String {
    case valid
    case expired
    case notFound = "not_found"
    case parseError = "parse_error"
}

private extension ISO8601DateFormatter {
    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
