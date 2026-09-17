//
//  ClipboardItem.swift
//  boringNotch
//

import AppKit
import Foundation

/// Reference to an image blob stored under Application Support/boringNotch/Clipboard/Blobs.
///
/// Only file *names* are persisted, never absolute paths: the sandbox container path
/// embeds the bundle identifier, so absolute paths would not survive a container move.
struct ClipboardBlobRef: Codable, Equatable, Sendable {
    /// Full-fidelity payload, written back verbatim on re-copy.
    var fileName: String
    /// Downscaled preview used by the card. Nil if thumbnail generation failed.
    var thumbFileName: String?
    /// UTI of the original representation, so re-copy hands back the same type.
    var utiIdentifier: String
    var byteCount: Int
    var pixelWidth: Int?
    var pixelHeight: Int?
}

/// Reference to a file copied from another app.
///
/// `bookmark` is best-effort: macOS grants an implicit read extension for file URLs on the
/// general pasteboard, but a persistent security-scoped bookmark cannot always be minted from
/// it. `path` is always present so that re-copy, reveal-in-Finder and icon lookup keep working
/// even when the bookmark is nil — see `ClipboardActionService`.
struct ClipboardFileRef: Codable, Equatable, Sendable {
    var bookmark: Data?
    var path: String
    var name: String

    var url: URL { URL(fileURLWithPath: path) }
}

enum ClipboardItemKind: Codable, Equatable, Sendable {
    case text(String)
    case link(URL)
    case image(blob: ClipboardBlobRef)
    case files([ClipboardFileRef])

    enum CodingKeys: String, CodingKey { case type, value }

    enum KindTag: String, Codable { case text, link, image, files }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindTag.self, forKey: .type)
        switch type {
        case .text:
            self = .text(try container.decode(String.self, forKey: .value))
        case .link:
            self = .link(try container.decode(URL.self, forKey: .value))
        case .image:
            self = .image(blob: try container.decode(ClipboardBlobRef.self, forKey: .value))
        case .files:
            self = .files(try container.decode([ClipboardFileRef].self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let string):
            try container.encode(KindTag.text, forKey: .type)
            try container.encode(string, forKey: .value)
        case .link(let url):
            try container.encode(KindTag.link, forKey: .type)
            try container.encode(url, forKey: .value)
        case .image(let blob):
            try container.encode(KindTag.image, forKey: .type)
            try container.encode(blob, forKey: .value)
        case .files(let refs):
            try container.encode(KindTag.files, forKey: .type)
            try container.encode(refs, forKey: .value)
        }
    }
}

/// A single entry in the clipboard history.
///
/// Deliberately **not** `@MainActor` (unlike `ShelfItem`). Keeping it actor-agnostic and
/// `Sendable` is what allows `ClipboardPersistenceService` to encode and write on a background
/// queue instead of blocking the main thread on every capture.
struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: ClipboardItemKind
    var createdAt: Date
    /// SHA256 of the payload. Persisted so image dedup does not require re-reading blobs.
    let contentHash: String
    var sourceBundleID: String?

    init(
        id: UUID = UUID(),
        kind: ClipboardItemKind,
        createdAt: Date = Date(),
        contentHash: String,
        sourceBundleID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.contentHash = contentHash
        self.sourceBundleID = sourceBundleID
    }
}

// MARK: - Presentation

extension ClipboardItem {
    /// Cap on how much of a long snippet we hand to SwiftUI. The card shows four lines; laying
    /// out a multi-megabyte string to render 200 characters is pure waste.
    private static let previewCharacterLimit = 400

    var previewText: String {
        switch kind {
        case .text(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count > Self.previewCharacterLimit
                ? String(trimmed.prefix(Self.previewCharacterLimit)) + "…"
                : trimmed
        case .link(let url):
            let s = url.absoluteString
            if s.hasPrefix("https://") { return String(s.dropFirst("https://".count)) }
            if s.hasPrefix("http://") { return String(s.dropFirst("http://".count)) }
            return s
        case .image(let blob):
            if let w = blob.pixelWidth, let h = blob.pixelHeight {
                return "Image · \(w)×\(h)"
            }
            return "Image"
        case .files(let refs):
            guard let first = refs.first else { return "" }
            return refs.count > 1 ? "\(first.name) +\(refs.count - 1) more" : first.name
        }
    }

    var iconSymbolName: String {
        switch kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .files: return "doc.on.doc"
        }
    }

    /// Deduplication key. Mirrors `ShelfItem.identityKey`.
    var identityKey: String {
        switch kind {
        case .text(let s):
            return "text://" + s
        case .link(let u):
            return "link://" + u.absoluteString
        case .image:
            return "image://" + contentHash
        case .files(let refs):
            return "files://" + refs.map(\.path).sorted().joined(separator: "|")
        }
    }
}
