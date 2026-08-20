import CryptoKit
import Foundation

public enum CodexHookAuthenticationResult: Equatable, Sendable {
    case valid
    case malformedInput
    case invalidSecret
    case invalidSignature
    case malformedPayload
    case expired
}

public enum CodexHookAuthenticator {
    private static let maximumPayloadBytes = 256 * 1024
    private static let maximumEncodedPayloadCharacters = (
        (maximumPayloadBytes + 2) / 3
    ) * 4
    private static let maximumAge: TimeInterval = 120

    public static func validate(
        payload: String,
        signature: String,
        secret: Data,
        now: Date = Date()
    ) -> CodexHookAuthenticationResult {
        guard !payload.isEmpty,
              payload.count <= maximumEncodedPayloadCharacters,
              signature.count == 43,
              let signatureData = decodeBase64URL(signature),
              signatureData.count == SHA256.byteCount else {
            return .malformedInput
        }
        guard secret.count == 32 else { return .invalidSecret }

        let key = SymmetricKey(data: secret)
        guard HMAC<SHA256>.isValidAuthenticationCode(
            signatureData,
            authenticating: Data(payload.utf8),
            using: key
        ) else {
            return .invalidSignature
        }
        guard let decodedPayload = decodeBase64URL(payload),
              let object = try? JSONSerialization.jsonObject(with: decodedPayload) as? [String: Any],
              let authentication = object["boring_notch_auth"] as? [String: Any],
              let timestamp = authentication["timestamp"] as? TimeInterval,
              let nonce = authentication["nonce"] as? String,
              nonce.count == 32 else {
            return .malformedPayload
        }

        let age = now.timeIntervalSince1970 - timestamp
        guard age >= -5, age <= maximumAge else { return .expired }
        return .valid
    }

    private static func decodeBase64URL(_ encoded: String) -> Data? {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}
