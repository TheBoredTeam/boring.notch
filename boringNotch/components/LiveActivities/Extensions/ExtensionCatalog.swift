// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Foundation

/// Public listing metadata. Price is descriptive; only an approved artifact
/// controls whether the native store can download a package.
struct ExtensionCatalog: Decodable, Sendable {
    static let maximumBytes = 2_000_000
    static let maximumItems = 500
    static let defaultURL = URL(string: "https://raw.githubusercontent.com/TheBoredTeam/boring-notch-extensions/main/catalog.json")
    static var officialURL: URL? {
        sourceURL(configuredValue: Bundle.main.object(forInfoDictionaryKey: "BoringNotchExtensionCatalogURL") as? String)
    }

    static func sourceURL(configuredValue: String?) -> URL? {
        guard let configuredValue else { return defaultURL }
        guard let url = URL(string: configuredValue), ExtensionCatalogURL.isSafeHTTPS(url) else { return nil }
        return url
    }

    let schemaVersion: Int
    let extensions: [ExtensionCatalogItem]

    static func decode(_ data: Data) throws -> ExtensionCatalog {
        guard data.count <= maximumBytes else { throw ExtensionStoreError.catalogTooLarge }
        let catalog: ExtensionCatalog
        do {
            // The registry compiles reviewed TOML sources into one JSON catalog.
            // XML and binary property lists remain readable for older sources.
            let firstByte = data.first { ![0x20, 0x09, 0x0a, 0x0d].contains($0) }
            if firstByte == 0x7b {
                catalog = try JSONDecoder().decode(Self.self, from: data)
            } else {
                catalog = try PropertyListDecoder().decode(Self.self, from: data)
            }
        }
        catch { throw ExtensionStoreError.invalidCatalog }
        guard catalog.schemaVersion == 1, catalog.extensions.count <= maximumItems,
              Set(catalog.extensions.map(\.id)).count == catalog.extensions.count,
              Set(catalog.extensions.map(\.slug)).count == catalog.extensions.count else {
            throw ExtensionStoreError.invalidCatalog
        }
        try catalog.extensions.forEach { try $0.validate() }
        return catalog
    }
}

struct ExtensionCatalogItem: Decodable, Equatable, Identifiable, Sendable {
    enum Status: String, Decodable, Sendable {
        case comingSoon = "coming-soon"
        case preview
        case available
    }

    struct Developer: Decodable, Equatable, Sendable {
        let name: String
        let url: URL

        private enum CodingKeys: String, CodingKey { case name, url }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decode(String.self, forKey: .name)
            url = try values.decodeCatalogURL(forKey: .url)
        }
    }

    struct Price: Decodable, Equatable, Sendable {
        let amount: Double
        let currency: String
        let billing: String
    }

    let id: String
    let slug: String
    let name: String
    let tagline: String
    let description: String
    let developer: Developer
    let categories: [String]
    let price: Price
    let status: Status
    let statusNote: String?
    let version: String
    let requirements: [String]
    let sourceURL: URL?
    let supportURL: URL?
    let artifact: ExtensionCatalogArtifact?
    private let productURL: URL?
    private let icon: String?
    private let artwork: String?

    var installableArtifact: ExtensionCatalogArtifact? {
        status == .available ? artifact : nil
    }

    var iconURL: URL? { icon.flatMap(ExtensionCatalogURL.assetURL) }
    var artworkURL: URL? { artwork.flatMap(ExtensionCatalogURL.assetURL) }

    var websiteURL: URL? { productURL ?? developer.url }

    private enum CodingKeys: String, CodingKey {
        case id, slug, name, tagline, description, developer, categories, price, status, statusNote
        case version, requirements, artifact, icon, artwork
        case sourceURL = "sourceUrl"
        case supportURL = "supportUrl"
        case productURL = "websiteUrl"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        slug = try values.decode(String.self, forKey: .slug)
        name = try values.decode(String.self, forKey: .name)
        tagline = try values.decode(String.self, forKey: .tagline)
        description = try values.decode(String.self, forKey: .description)
        developer = try values.decode(Developer.self, forKey: .developer)
        categories = try values.decode([String].self, forKey: .categories)
        price = try values.decode(Price.self, forKey: .price)
        status = try values.decode(Status.self, forKey: .status)
        statusNote = try values.decodeIfPresent(String.self, forKey: .statusNote)
        version = try values.decode(String.self, forKey: .version)
        requirements = try values.decode([String].self, forKey: .requirements)
        sourceURL = try values.decodeCatalogURLIfPresent(forKey: .sourceURL)
        supportURL = try values.decodeCatalogURLIfPresent(forKey: .supportURL)
        productURL = try values.decodeCatalogURLIfPresent(forKey: .productURL)
        artifact = try values.decodeIfPresent(ExtensionCatalogArtifact.self, forKey: .artifact)
        icon = try values.decodeIfPresent(String.self, forKey: .icon)
        artwork = try values.decodeIfPresent(String.self, forKey: .artwork)
    }

    func validate() throws {
        guard id.utf8.count <= 128,
              id.range(of: #"\A[a-z][a-z0-9]*(\.[a-z0-9-]+)+\z"#, options: .regularExpression) != nil,
              slug.utf8.count <= 128,
              slug.range(of: #"\A[a-z0-9]+(?:-[a-z0-9]+)*\z"#, options: .regularExpression) != nil,
              Self.validText(name, maximum: 128), Self.validText(tagline, maximum: 512),
              Self.validText(description, maximum: 16_384), Self.validText(version, maximum: 64),
              Self.validText(developer.name, maximum: 128), ExtensionCatalogURL.isSafeHTTPS(developer.url),
              categories.count <= 16, categories.allSatisfy({ Self.validText($0, maximum: 64) }),
              requirements.count <= 32, requirements.allSatisfy({ Self.validText($0, maximum: 1_024) }),
              statusNote.map({ Self.validText($0, maximum: 4_096) }) ?? true,
              price.amount.isFinite, price.amount >= 0, price.amount <= 1_000_000,
              price.currency.range(of: #"\A[A-Z]{3}\z"#, options: .regularExpression) != nil,
              ["free", "one-time", "monthly", "yearly"].contains(price.billing),
              (price.amount == 0) == (price.billing == "free"),
              sourceURL.map(ExtensionCatalogURL.isSafeHTTPS) ?? true,
              supportURL.map(ExtensionCatalogURL.isSafeHTTPS) ?? true,
              productURL.map(ExtensionCatalogURL.isSafeHTTPS) ?? true,
              icon.map({ ExtensionCatalogURL.assetURL($0) != nil }) ?? true,
              artwork.map({ ExtensionCatalogURL.assetURL($0) != nil }) ?? true else {
            throw ExtensionStoreError.invalidCatalog
        }
        guard status != .available || artifact != nil else { throw ExtensionStoreError.invalidCatalog }
        if let artifact {
            try artifact.validate()
            guard artifact.version == version else { throw ExtensionStoreError.invalidCatalog }
        }
    }

    private static func validText(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= maximum
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.subtracting(.newlines).contains($0) }
    }
}

struct ExtensionCatalogArtifact: Decodable, Equatable, Sendable {
    let url: URL
    let sha256: String
    let publisherTeamID: String
    let version: String
    let apiVersion: Int

    private enum CodingKeys: String, CodingKey { case downloadURL, url, sha256, publisherTeamID, version, apiVersion }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let downloadURL = try values.decodeCatalogURLIfPresent(forKey: .downloadURL)
        let legacyURL = try values.decodeCatalogURLIfPresent(forKey: .url)
        guard let resolvedURL = downloadURL ?? legacyURL,
              downloadURL == nil || legacyURL == nil || downloadURL == legacyURL else {
            throw ExtensionStoreError.invalidCatalog
        }
        url = resolvedURL
        sha256 = try values.decode(String.self, forKey: .sha256)
        publisherTeamID = try values.decode(String.self, forKey: .publisherTeamID)
        version = try values.decode(String.self, forKey: .version)
        apiVersion = try values.decode(Int.self, forKey: .apiVersion)
    }

    func validate() throws {
        guard ExtensionCatalogURL.isSafeHTTPS(url), url.pathExtension.lowercased() == "zip",
              sha256.range(of: #"\A[A-Fa-f0-9]{64}\z"#, options: .regularExpression) != nil,
              publisherTeamID.range(of: #"\A[A-Z0-9]{10}\z"#, options: .regularExpression) != nil,
              !version.isEmpty, version.trimmingCharacters(in: .whitespacesAndNewlines) == version,
              version.rangeOfCharacter(from: .controlCharacters) == nil, version.utf8.count <= 64,
              apiVersion == 1 else { throw ExtensionStoreError.invalidCatalog }
    }
}

private extension KeyedDecodingContainer {
    // PropertyListDecoder does not give URL the JSON decoder's string special
    // case. The public format deliberately uses ordinary strings in both.
    func decodeCatalogURL(forKey key: Key) throws -> URL {
        let value = try decode(String.self, forKey: key)
        guard let url = URL(string: value) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid URL string")
        }
        return url
    }

    func decodeCatalogURLIfPresent(forKey key: Key) throws -> URL? {
        guard let value = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let url = URL(string: value) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid URL string")
        }
        return url
    }
}

enum ExtensionCatalogURL {
    static func isSafeHTTPS(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.fragment == nil,
              url.absoluteString.utf8.count <= 4_096 else { return false }
        return true
    }

    static func assetURL(_ value: String) -> URL? {
        if let absolute = URL(string: value), isSafeHTTPS(absolute) { return absolute }
        guard value.hasPrefix("assets/extensions/"), !value.contains("\\"), !value.contains("%"),
              !value.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".."
              }), let url = URL(string: "https://theboring.name/" + value), isSafeHTTPS(url),
              ["svg", "png", "webp", "jpg", "jpeg"].contains(url.pathExtension.lowercased()),
              url.query == nil, url.path.hasPrefix("/assets/extensions/"),
              !url.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        return url
    }
}

enum ExtensionStoreError: LocalizedError, Equatable {
    case invalidCatalog, catalogTooLarge, unavailable, downloadInProgress
    case invalidResponse, unsafeURL, downloadTooLarge, checksumMismatch, emptyDownload

    var errorDescription: String? {
        switch self {
        case .invalidCatalog: return "The extension catalog is not valid. Try refreshing it later."
        case .catalogTooLarge: return "The extension catalog exceeds the supported size."
        case .unavailable: return "This extension does not have an approved download yet."
        case .downloadInProgress: return "Another extension download is already in progress."
        case .invalidResponse: return "The extension server returned an unexpected response."
        case .unsafeURL: return "Extension downloads require an HTTPS address without embedded credentials."
        case .downloadTooLarge: return "This extension exceeds the 100 MB download limit."
        case .checksumMismatch: return "The downloaded extension does not match its approved checksum."
        case .emptyDownload: return "The extension download was empty."
        }
    }
}
