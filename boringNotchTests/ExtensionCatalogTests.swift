// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Foundation
import XCTest
@testable import boringNotch

enum StoreCatalogFixture {
    static func item(status: String = "available", paid: Bool = false, artifact: Bool = true) -> [String: Any] {
        var value: [String: Any] = [
            "id": "org.example.focus", "slug": "focus", "name": "Focus",
            "tagline": "A focus timer", "description": "A sample independent extension.",
            "developer": ["name": "Example publisher", "url": "https://example.org/"],
            "categories": ["Productivity"],
            "price": ["amount": paid ? 4.99 : 0, "currency": "USD", "billing": paid ? "one-time" : "free"],
            "status": status, "statusNote": "Sample catalog fixture", "version": "1.0.0",
            "requirements": ["macOS 14 or later"], "sourceUrl": "https://example.org/source",
            "supportUrl": "https://example.org/support", "icon": "assets/extensions/focus.svg"
        ]
        if artifact {
            value["artifact"] = ["url": "https://downloads.example.org/focus.zip",
                                 "sha256": String(repeating: "a", count: 64),
                                 "publisherTeamID": "AB12CD34EF", "version": "1.0.0", "apiVersion": 1]
        }
        return value
    }

    static func data(_ items: [[String: Any]], schemaVersion: Int = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": schemaVersion, "extensions": items])
    }

    static func decode(_ item: [String: Any]) throws -> ExtensionCatalogItem {
        let catalog = try ExtensionCatalog.decode(data([item]))
        return try XCTUnwrap(catalog.extensions.first)
    }
}

final class ExtensionCatalogTests: XCTestCase {
    func testFreeAndPaidAvailableArtifactsBothAllowInstallation() throws {
        let free = try StoreCatalogFixture.decode(StoreCatalogFixture.item())
        let paid = try StoreCatalogFixture.decode(StoreCatalogFixture.item(paid: true))
        XCTAssertNotNil(free.installableArtifact)
        XCTAssertNotNil(paid.installableArtifact)
        XCTAssertEqual(free.installableArtifact, paid.installableArtifact)
    }

    func testPreviewComingSoonAndMissingArtifactNeverEnableInstall() throws {
        for status in ["preview", "coming-soon"] {
            let entry = try StoreCatalogFixture.decode(StoreCatalogFixture.item(status: status))
            XCTAssertNil(entry.installableArtifact)
            XCTAssertNotNil(entry.sourceURL)
            XCTAssertEqual(entry.websiteURL, entry.developer.url)
        }
        XCTAssertThrowsError(try StoreCatalogFixture.decode(StoreCatalogFixture.item(artifact: false)))
    }

    func testUnknownProductAndPaymentFieldsAreIgnored() throws {
        var value = StoreCatalogFixture.item(paid: true)
        value["purchaseUrl"] = "https://publisher.example.org/pay"
        value["licenseSDK"] = ["notAHostContract": true]
        value["features"] = [["title": "Future metadata"]]
        XCTAssertNotNil(try StoreCatalogFixture.decode(value).installableArtifact)
    }

    func testDuplicateIDsAndSlugsAreRejected() throws {
        let first = StoreCatalogFixture.item()
        XCTAssertThrowsError(try ExtensionCatalog.decode(StoreCatalogFixture.data([first, first])))
        var other = first
        other["id"] = "org.example.other"
        XCTAssertThrowsError(try ExtensionCatalog.decode(StoreCatalogFixture.data([first, other])))
    }

    func testArtifactIdentityVersionHashAndAPIMustBeExact() throws {
        let invalidFields: [(String, Any)] = [
            ("version", "2.0.0"), ("sha256", String(repeating: "a", count: 63)),
            ("sha256", String(repeating: "g", count: 64)), ("sha256", String(repeating: "a", count: 64) + "\n"),
            ("publisherTeamID", "AB12CD34EF\n"), ("publisherTeamID", "short"), ("apiVersion", 2)
        ]
        for (field, invalid) in invalidFields {
            var item = StoreCatalogFixture.item()
            var artifact = try XCTUnwrap(item["artifact"] as? [String: Any])
            artifact[field] = invalid
            item["artifact"] = artifact
            XCTAssertThrowsError(try StoreCatalogFixture.decode(item), field)
        }
    }

    func testUnsafeArtifactAndPublisherURLsAreRejected() throws {
        for url in ["http://example.org/a.zip", "file:///tmp/a.zip", "https://user:secret@example.org/a.zip",
                    "https://example.org/a.zip#fragment", "https://example.org/a.dmg", "/relative.zip"] {
            var item = StoreCatalogFixture.item()
            var artifact = try XCTUnwrap(item["artifact"] as? [String: Any])
            artifact["url"] = url
            item["artifact"] = artifact
            XCTAssertThrowsError(try StoreCatalogFixture.decode(item), url)
        }
        var item = StoreCatalogFixture.item()
        item["developer"] = ["name": "Example", "url": "https://credentials@example.org/"]
        XCTAssertThrowsError(try StoreCatalogFixture.decode(item))
    }

    func testIdentifierAndCurrencyValidationRejectsTrailingNewlines() throws {
        for field in ["id", "slug"] {
            var item = StoreCatalogFixture.item()
            item[field] = (try XCTUnwrap(item[field] as? String)) + "\n"
            XCTAssertThrowsError(try StoreCatalogFixture.decode(item))
        }
        var item = StoreCatalogFixture.item()
        item["price"] = ["amount": 0, "currency": "USD\n", "billing": "free"]
        XCTAssertThrowsError(try StoreCatalogFixture.decode(item))
    }

    func testAssetPathsCannotEscapeThePublishedAssetDirectory() {
        XCTAssertNotNil(ExtensionCatalogURL.assetURL("assets/extensions/focus.svg"))
        XCTAssertEqual(ExtensionCatalogURL.assetURL("https://another.example.org/a.svg")?.host, "another.example.org")
        for path in ["assets/extensions/../secret.svg", "assets/extensions/%2e%2e/secret.svg",
                     "assets/extensions/%252e%252e/secret.svg", "assets/extensions/a.svg?token=secret",
                     "http://another.example.org/a.svg", "https://user:pass@another.example.org/a.svg",
                     "assets/extensions//a.svg"] {
            XCTAssertNil(ExtensionCatalogURL.assetURL(path), path)
        }
    }

    func testGeneratedJSONAndLegacyPlistsAcceptCanonicalPublicDownloadURL() throws {
        var item = StoreCatalogFixture.item()
        var artifact = try XCTUnwrap(item["artifact"] as? [String: Any])
        artifact["downloadURL"] = artifact.removeValue(forKey: "url")
        item["artifact"] = artifact
        item["icon"] = "https://raw.githubusercontent.com/example/catalog/main/icons/focus.png"
        item["artwork"] = "https://publisher.example.org/focus.png"
        let legacyPlists = try [PropertyListSerialization.PropertyListFormat.xml, .binary].map { format in
            try PropertyListSerialization.data(fromPropertyList: ["schemaVersion": 1, "extensions": [item]],
                                               format: format, options: 0)
        }
        for bytes in [try StoreCatalogFixture.data([item])] + legacyPlists {
            let decoded = try XCTUnwrap(ExtensionCatalog.decode(bytes).extensions.first)
            XCTAssertEqual(decoded.installableArtifact?.url.absoluteString, "https://downloads.example.org/focus.zip")
            XCTAssertEqual(decoded.iconURL?.host, "raw.githubusercontent.com")
            XCTAssertEqual(decoded.artworkURL?.host, "publisher.example.org")
            XCTAssertEqual(decoded.installableArtifact?.publisherTeamID, "AB12CD34EF")
        }
    }

    func testConflictingDownloadURLAliasesAndIncompleteAvailableListingsAreRejected() throws {
        var item = StoreCatalogFixture.item()
        var artifact = try XCTUnwrap(item["artifact"] as? [String: Any])
        artifact["downloadURL"] = artifact["url"]
        item["artifact"] = artifact
        XCTAssertNotNil(try StoreCatalogFixture.decode(item).installableArtifact)
        artifact["downloadURL"] = "https://other.example.org/different.zip"
        item["artifact"] = artifact
        XCTAssertThrowsError(try StoreCatalogFixture.decode(item))
        artifact.removeValue(forKey: "url")
        artifact["downloadURL"] = "http://example.org/insecure.zip"
        item["artifact"] = artifact
        XCTAssertThrowsError(try StoreCatalogFixture.decode(item))
        item.removeValue(forKey: "artifact")
        let plist = try PropertyListSerialization.data(fromPropertyList: ["schemaVersion": 1, "extensions": [item]],
                                                       format: .xml, options: 0)
        XCTAssertThrowsError(try ExtensionCatalog.decode(plist))
    }

    func testEndpointConfigurationUsesGitHubDefaultAndRejectsUnsafeOverrides() {
        XCTAssertEqual(ExtensionCatalog.sourceURL(configuredValue: nil)?.absoluteString,
                       "https://raw.githubusercontent.com/TheBoredTeam/boring-notch-extensions/main/catalog.json")
        XCTAssertEqual(ExtensionCatalog.sourceURL(configuredValue: "https://example.org/catalog.json")?.host, "example.org")
        XCTAssertEqual(ExtensionCatalog.sourceURL(configuredValue: "https://example.org/catalog.plist")?.host, "example.org")
        for invalid in ["", "file:///tmp/catalog.json", "http://example.org/catalog.json",
                        "https://user:secret@example.org/catalog.json", "https://example.org/catalog.json#fragment"] {
            XCTAssertNil(ExtensionCatalog.sourceURL(configuredValue: invalid))
        }
    }

    func testMissingProductWebsiteUsesDeveloperURLWithoutInventingAListingPage() throws {
        var value = StoreCatalogFixture.item()
        value["slug"] = "new-independent-listing"
        let item = try StoreCatalogFixture.decode(value)
        XCTAssertEqual(item.websiteURL?.absoluteString, "https://example.org/")
        XCTAssertEqual(item.websiteURL, item.developer.url)
    }

    func testExplicitProductWebsiteIsUsedByJSONAndPlistListings() throws {
        var value = StoreCatalogFixture.item()
        value["websiteUrl"] = "https://publisher.example.org/products/focus?source=notch"
        let jsonItem = try StoreCatalogFixture.decode(value)
        XCTAssertEqual(jsonItem.websiteURL?.absoluteString, value["websiteUrl"] as? String)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["schemaVersion": 1, "extensions": [value]],
                                                       format: .xml, options: 0)
        let plistItem = try XCTUnwrap(ExtensionCatalog.decode(plist).extensions.first)
        XCTAssertEqual(plistItem.websiteURL, jsonItem.websiteURL)
        XCTAssertNotEqual(plistItem.websiteURL, plistItem.developer.url)
    }

    func testUnsafeProductWebsiteIsRejectedInsteadOfSilentlyFallingBack() throws {
        for url in ["", "/relative-product", "http://example.org/product", "file:///tmp/product",
                    "https://user:secret@example.org/product", "https://example.org/product#fragment"] {
            var value = StoreCatalogFixture.item()
            value["websiteUrl"] = url
            XCTAssertThrowsError(try StoreCatalogFixture.decode(value), url)
        }
    }

    func testCatalogSizeEntryAndSchemaLimitsAreEnforced() throws {
        XCTAssertThrowsError(try ExtensionCatalog.decode(Data(repeating: 0, count: ExtensionCatalog.maximumBytes + 1)))
        XCTAssertThrowsError(try ExtensionCatalog.decode(StoreCatalogFixture.data([], schemaVersion: 2)))
        let entries = (0...ExtensionCatalog.maximumItems).map { index -> [String: Any] in
            var entry = StoreCatalogFixture.item()
            entry["id"] = "org.example.item\(index)"
            entry["slug"] = "item-\(index)"
            return entry
        }
        XCTAssertThrowsError(try ExtensionCatalog.decode(StoreCatalogFixture.data(entries)))
    }
}
