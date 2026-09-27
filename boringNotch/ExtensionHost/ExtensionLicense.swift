//
//  ExtensionLicense.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import CryptoKit
import Combine
import Foundation
import Security

struct ExtensionLicenseEnvelope: Codable {
    let keyID: String
    let payload: String
    let signature: String
}

struct ExtensionLicenseClaims: Codable, Equatable {
    let version: Int
    let issuer: String
    let licenseID: String
    let productID: String
    let deviceID: String
    let issuedAt: Double
    let lifetime: Bool
}

enum ExtensionLicenseError: LocalizedError {
    case notConfigured, invalidCode, invalidReceipt, storage, rejected, unavailable
    var errorDescription: String? {
        switch self {
        case .notConfigured: "License activation is not configured in this build."
        case .invalidCode: "Enter the 14-character license code from your purchase."
        case .invalidReceipt: "The license signature, product, or Mac does not match."
        case .storage: "The license could not be saved in your Mac’s Keychain."
        case .rejected: "This code is invalid for this extension or has reached its Mac limit."
        case .unavailable: "The license service is unavailable. Please try again."
        }
    }
}

enum ExtensionLicenseVerifier {
    static func verify(_ envelope: ExtensionLicenseEnvelope, keys: [String: String],
                       productID: String, deviceID: String, now: Date = Date()) throws -> ExtensionLicenseClaims {
        guard let encodedKey = keys[envelope.keyID], let key = Data(base64Encoded: encodedKey),
              let payload = Data(base64Encoded: envelope.payload), payload.count < 16_384,
              let signature = Data(base64Encoded: envelope.signature),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key) else {
            throw ExtensionLicenseError.invalidReceipt
        }
        let message = Data("boring-notch-license:v1\n".utf8) + payload
        guard publicKey.isValidSignature(signature, for: message) else { throw ExtensionLicenseError.invalidReceipt }
        let claims = try JSONDecoder().decode(ExtensionLicenseClaims.self, from: payload)
        guard claims.version == 1, claims.issuer == "theboringteam.boringnotch", claims.lifetime,
              !claims.licenseID.isEmpty, claims.productID == productID, claims.deviceID == deviceID,
              claims.issuedAt.isFinite, claims.issuedAt > 0, claims.issuedAt <= now.timeIntervalSince1970 + 300
        else { throw ExtensionLicenseError.invalidReceipt }
        return claims
    }

    static func normalizedCode(_ input: String) throws -> String {
        let code = input.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        guard code.range(of: #"^[A-HJ-NP-Z2-9]{14}$"#, options: .regularExpression) != nil else {
            throw ExtensionLicenseError.invalidCode
        }
        return code
    }
}

@MainActor
final class ExtensionLicenseStore: ObservableObject {
    static let shared = ExtensionLicenseStore()
    @Published private(set) var licensedProducts = Set<String>()
    @Published private(set) var activatingProduct: String?
    @Published var message: String?
    private var receipts: [String: ExtensionLicenseEnvelope] = [:]
    private var deviceID = ""
    private var task: Task<Void, Never>?

    private var publicKeys: [String: String] {
        Bundle.main.object(forInfoDictionaryKey: "BNExtensionLicensePublicKeys") as? [String: String] ?? [:]
    }
    private var serverURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "BNExtensionLicenseServerURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    var isConfigured: Bool { serverURL != nil && !publicKeys.isEmpty && !deviceID.isEmpty }

    private init() {
        guard !publicKeys.isEmpty else { return }
        #if DEBUG
        // A local launch can use a Go-issued receipt without touching the user's Keychain.
        // The public key is still pinned in this specific test app's signed Info.plist.
        if ProcessInfo.processInfo.environment["BN_ALLOW_DEVELOPMENT_EXTENSIONS"] == "1",
           let path = ProcessInfo.processInfo.environment["BN_EXTENSION_LICENSE_FIXTURE"] {
            struct Fixture: Decodable {
                let receipt: ExtensionLicenseEnvelope
                let productID: String
                let deviceID: String
            }
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                guard data.count < 32_768 else { throw ExtensionLicenseError.invalidReceipt }
                let fixture = try JSONDecoder().decode(Fixture.self, from: data)
                _ = try ExtensionLicenseVerifier.verify(fixture.receipt, keys: publicKeys,
                    productID: fixture.productID, deviceID: fixture.deviceID)
                deviceID = fixture.deviceID
                receipts[fixture.productID] = fixture.receipt
                licensedProducts.insert(fixture.productID)
                message = "Local test license active."
            } catch { message = error.localizedDescription }
            return
        }
        #endif
        do {
            if let stored = try read(account: "device-v1"), let id = String(data: stored, encoding: .utf8), !id.isEmpty {
                deviceID = id
            } else {
                let id = UUID().uuidString.lowercased()
                try save(Data(id.utf8), account: "device-v1")
                deviceID = id
            }
            if let stored = try read(account: "receipts-v1") {
                receipts = try JSONDecoder().decode([String: ExtensionLicenseEnvelope].self, from: stored)
            }
            for (product, receipt) in receipts {
                if (try? ExtensionLicenseVerifier.verify(receipt, keys: publicKeys, productID: product, deviceID: deviceID)) != nil {
                    licensedProducts.insert(product)
                }
            }
        } catch { message = error.localizedDescription }
    }

    func activate(code input: String, productID: String) {
        guard activatingProduct == nil else { return }
        do {
            let code = try ExtensionLicenseVerifier.normalizedCode(input)
            guard isConfigured, let serverURL else { throw ExtensionLicenseError.notConfigured }
            activatingProduct = productID
            message = nil
            task = Task { [weak self] in
                guard let self else { return }
                defer { self.activatingProduct = nil }
                do {
                    var request = URLRequest(url: serverURL.appendingPathComponent("v1/licenses/activate"), timeoutInterval: 20)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(["code": code, "productID": productID, "deviceID": self.deviceID])
                    let (data, response) = try await URLSession.shared.data(for: request)
                    try Task.checkCancellation()
                    guard let status = (response as? HTTPURLResponse)?.statusCode else { throw ExtensionLicenseError.unavailable }
                    guard status == 200 else {
                        if [400, 403, 404, 409].contains(status) { throw ExtensionLicenseError.rejected }
                        throw ExtensionLicenseError.unavailable
                    }
                    guard data.count < 32_768 else { throw ExtensionLicenseError.invalidReceipt }
                    let envelope = try JSONDecoder().decode(ExtensionLicenseEnvelope.self, from: data)
                    _ = try ExtensionLicenseVerifier.verify(envelope, keys: self.publicKeys, productID: productID, deviceID: self.deviceID)
                    var receipts = self.receipts
                    receipts[productID] = envelope
                    try self.save(JSONEncoder().encode(receipts), account: "receipts-v1")
                    self.receipts = receipts
                    self.licensedProducts.insert(productID)
                    self.message = "Permanently unlocked on this Mac."
                } catch {
                    if !Task.isCancelled { self.message = error.localizedDescription }
                }
            }
        } catch { message = error.localizedDescription }
    }

    private func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "theboringteam.boringnotch.extensions",
         kSecAttrAccount as String: account]
    }
    private func read(account: String) throws -> Data? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ExtensionLicenseError.storage }
        return data
    }
    private func save(_ data: Data, account: String) throws {
        var query = query(account: account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw ExtensionLicenseError.storage }
        } else if status != errSecSuccess { throw ExtensionLicenseError.storage }
    }
    func stop() { task?.cancel(); task = nil }
}
