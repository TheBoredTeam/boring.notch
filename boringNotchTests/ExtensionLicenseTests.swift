//
//  ExtensionLicenseTests.swift
//  boringNotchTests
//
import CryptoKit
import XCTest
@testable import boringNotch

final class ExtensionLicenseTests: XCTestCase {
    private let product = "theboringteam.boringnotch.lockscreen-lyrics"
    private let device = "58f02685-adce-42af-a786-d9f30d3e46be"

    private func receipt(key: Curve25519.Signing.PrivateKey, issuedAt: Double = 1_700_000_000,
                         lifetime: Bool = true) throws -> ExtensionLicenseEnvelope {
        let claims = ExtensionLicenseClaims(version: 1, issuer: "theboringteam.boringnotch", licenseID: "test-license",
            productID: product, deviceID: device, issuedAt: issuedAt, lifetime: lifetime)
        let payload = try JSONEncoder().encode(claims)
        let signature = try key.signature(for: Data("boring-notch-license:v1\n".utf8) + payload)
        return ExtensionLicenseEnvelope(keyID: "test", payload: payload.base64EncodedString(), signature: signature.base64EncodedString())
    }

    func testPermanentReceiptRemainsValidOffline() throws {
        let key = Curve25519.Signing.PrivateKey()
        let keys = ["test": key.publicKey.rawRepresentation.base64EncodedString()]
        let envelope = try receipt(key: key)
        let claims = try ExtensionLicenseVerifier.verify(envelope, keys: keys, productID: product, deviceID: device,
                                                         now: Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertTrue(claims.lifetime)
    }

    func testWrongProductDeviceKeyAndPayloadAreRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let keys = ["test": key.publicKey.rawRepresentation.base64EncodedString()]
        let envelope = try receipt(key: key)
        XCTAssertThrowsError(try ExtensionLicenseVerifier.verify(envelope, keys: keys, productID: "other", deviceID: device))
        XCTAssertThrowsError(try ExtensionLicenseVerifier.verify(envelope, keys: keys, productID: product, deviceID: "other"))
        XCTAssertThrowsError(try ExtensionLicenseVerifier.verify(envelope, keys: [:], productID: product, deviceID: device))
        let badKeys = ["test": Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()]
        XCTAssertThrowsError(try ExtensionLicenseVerifier.verify(envelope, keys: badKeys, productID: product, deviceID: device))
        let tampered = ExtensionLicenseEnvelope(keyID: "test", payload: Data("{}".utf8).base64EncodedString(), signature: envelope.signature)
        XCTAssertThrowsError(try ExtensionLicenseVerifier.verify(tampered, keys: keys, productID: product, deviceID: device))
    }

    func testFutureAndNonPermanentReceiptAreRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let keys = ["test": key.publicKey.rawRepresentation.base64EncodedString()]
        XCTAssertThrowsError(try ExtensionLicenseVerifier.verify(receipt(key: key, issuedAt: Date().timeIntervalSince1970 + 600),
                                                                 keys: keys, productID: product, deviceID: device))
        XCTAssertThrowsError(try ExtensionLicenseVerifier.verify(receipt(key: key, lifetime: false),
                                                                 keys: keys, productID: product, deviceID: device))
    }

    func testShortCodeNormalizationAndAmbiguousCharacters() throws {
        XCTAssertEqual(try ExtensionLicenseVerifier.normalizedCode("abcd-efgh-jkmn-pq"), "ABCDEFGHJKMNPQ")
        XCTAssertThrowsError(try ExtensionLicenseVerifier.normalizedCode("ABCDEF"))
        XCTAssertThrowsError(try ExtensionLicenseVerifier.normalizedCode("ABCDEFGHIJKLMN"))
        XCTAssertThrowsError(try ExtensionLicenseVerifier.normalizedCode("00000000000000"))
    }
}
