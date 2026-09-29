// SPDX-License-Identifier: GPL-3.0-only

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
            XCTAssertEqual(entry.websiteURL?.host, "theboring.name")
        }
        XCTAssertNil(try StoreCatalogFixture.decode(StoreCatalogFixture.item(artifact: false)).installableArtifact)
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
        for path in ["assets/extensions/../secret.svg", "assets/extensions/%2e%2e/secret.svg",
                     "assets/extensions/%252e%252e/secret.svg", "assets/extensions/a.svg?token=secret",
                     "https://another.example.org/a.svg", "assets/extensions//a.svg"] {
            XCTAssertNil(ExtensionCatalogURL.assetURL(path), path)
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
