import CryptoKit
import Darwin
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

public enum CodexHookSecretStoreError: LocalizedError, Equatable, Sendable {
    case invalidGeneratedSecret
    case unsafeExistingFile
    case system(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidGeneratedSecret:
            "The generated Codex hook secret is invalid."
        case .unsafeExistingFile:
            "The existing Codex hook secret is not a safe owner-only regular file."
        case .system:
            "The Codex hook secret could not be accessed safely."
        }
    }
}

public enum CodexHookSecretStore {
    private static let secretLength = 32
    private static let ownerOnlyPermissions: mode_t = 0o600

    public static func load(at url: URL) throws -> Data {
        try loadExistingSecret(at: url)
    }

    public static func loadOrCreate(
        at url: URL,
        generator: () throws -> Data
    ) throws -> Data {
        let existingDescriptor = openDescriptor(
            at: url,
            flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        if existingDescriptor >= 0 {
            return try loadValidatedSecret(from: existingDescriptor)
        }

        let existingError = errno
        guard existingError == ENOENT else {
            throw CodexHookSecretStoreError.system(existingError)
        }

        let secret = try generator()
        guard secret.count == secretLength else {
            throw CodexHookSecretStoreError.invalidGeneratedSecret
        }

        let createdDescriptor = openDescriptor(
            at: url,
            flags: O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode: ownerOnlyPermissions
        )
        if createdDescriptor < 0 {
            let creationError = errno
            if creationError == EEXIST {
                return try loadExistingSecret(at: url)
            }
            throw CodexHookSecretStoreError.system(creationError)
        }

        var keepCreatedFile = false
        defer {
            Darwin.close(createdDescriptor)
            if !keepCreatedFile {
                _ = url.path.withCString(Darwin.unlink)
            }
        }

        guard Darwin.fchmod(createdDescriptor, ownerOnlyPermissions) == 0 else {
            throw CodexHookSecretStoreError.system(errno)
        }
        try clearExtendedACL(from: createdDescriptor)
        try write(secret, to: createdDescriptor)
        guard Darwin.fsync(createdDescriptor) == 0 else {
            throw CodexHookSecretStoreError.system(errno)
        }
        try validate(descriptor: createdDescriptor)
        keepCreatedFile = true
        return secret
    }

    private static func loadExistingSecret(at url: URL) throws -> Data {
        let descriptor = openDescriptor(
            at: url,
            flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        guard descriptor >= 0 else {
            throw CodexHookSecretStoreError.system(errno)
        }
        return try loadValidatedSecret(from: descriptor)
    }

    private static func loadValidatedSecret(from descriptor: Int32) throws -> Data {
        defer { Darwin.close(descriptor) }
        try validate(descriptor: descriptor)
        let secret = try readSecret(from: descriptor)
        try validate(descriptor: descriptor)
        return secret
    }

    private static func validate(descriptor: Int32) throws {
        var attributes = stat()
        guard Darwin.fstat(descriptor, &attributes) == 0 else {
            throw CodexHookSecretStoreError.system(errno)
        }
        let fileType = attributes.st_mode & mode_t(S_IFMT)
        let permissions = attributes.st_mode & mode_t(0o777)
        guard fileType == mode_t(S_IFREG),
              attributes.st_uid == geteuid(),
              attributes.st_nlink == 1,
              permissions == ownerOnlyPermissions,
              attributes.st_size == off_t(secretLength),
              try !hasExtendedACLEntries(on: descriptor) else {
            throw CodexHookSecretStoreError.unsafeExistingFile
        }
    }

    private static func hasExtendedACLEntries(on descriptor: Int32) throws -> Bool {
        errno = 0
        if let accessList = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) {
            acl_free(UnsafeMutableRawPointer(accessList))
            return true
        }
        let accessListError = errno
        if accessListError == ENOENT { return false }
        throw CodexHookSecretStoreError.system(accessListError)
    }

    static func clearExtendedACL(from descriptor: Int32) throws {
        guard let emptyAccessList = acl_init(0) else {
            throw CodexHookSecretStoreError.system(errno)
        }
        defer { acl_free(UnsafeMutableRawPointer(emptyAccessList)) }
        guard acl_set_fd_np(descriptor, emptyAccessList, ACL_TYPE_EXTENDED) == 0 else {
            throw CodexHookSecretStoreError.system(errno)
        }
    }

    private static func readSecret(from descriptor: Int32) throws -> Data {
        var secret = Data(count: secretLength)
        var offset = 0
        try secret.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw CodexHookSecretStoreError.unsafeExistingFile
            }
            while offset < secretLength {
                let result = Darwin.read(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    secretLength - offset
                )
                if result < 0, errno == EINTR { continue }
                guard result > 0 else {
                    if result < 0 {
                        throw CodexHookSecretStoreError.system(errno)
                    }
                    throw CodexHookSecretStoreError.unsafeExistingFile
                }
                offset += result
            }
        }
        return secret
    }

    private static func write(_ data: Data, to descriptor: Int32) throws {
        var offset = 0
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw CodexHookSecretStoreError.invalidGeneratedSecret
            }
            while offset < data.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset
                )
                if result < 0, errno == EINTR { continue }
                guard result > 0 else {
                    throw CodexHookSecretStoreError.system(errno)
                }
                offset += result
            }
        }
    }

    private static func openDescriptor(
        at url: URL,
        flags: Int32,
        mode: mode_t? = nil
    ) -> Int32 {
        url.path.withCString { path in
            if let mode {
                Darwin.open(path, flags, mode)
            } else {
                Darwin.open(path, flags)
            }
        }
    }
}
