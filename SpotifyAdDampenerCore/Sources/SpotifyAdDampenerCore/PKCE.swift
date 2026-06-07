import CryptoKit
import Foundation

public struct PKCEPair: Equatable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String, challenge: String) {
        self.verifier = verifier
        self.challenge = challenge
    }
}

public enum PKCEError: Error, Equatable {
    case invalidByteCount
    case invalidAuthorizationURL
}

public enum PKCE {
    private static let verifierCharacters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func generateVerifier(byteCount: Int = 64) throws -> String {
        guard (32...96).contains(byteCount) else { throw PKCEError.invalidByteCount }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw PKCEError.invalidByteCount }
        return String(bytes.map { verifierCharacters[Int($0) % verifierCharacters.count] })
    }

    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedStringWithoutPadding()
    }

    public static func pair(byteCount: Int = 64) throws -> PKCEPair {
        let verifier = try generateVerifier(byteCount: byteCount)
        return PKCEPair(verifier: verifier, challenge: challenge(for: verifier))
    }

    public static func authorizationURL(clientID: String, redirectURI: String, scopes: [String], state: String, codeChallenge: String) throws -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge)
        ]
        guard let url = components.url else { throw PKCEError.invalidAuthorizationURL }
        return url
    }
}

private extension Data {
    func base64URLEncodedStringWithoutPadding() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
