// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import AppKit
import Foundation
import ImageIO

enum ExtensionTabPresentation: String, Codable, Hashable, Sendable {
    case regular
    case compact
}

/// Finite native points proposed by the host, independent of SwiftUI and the
/// extension's preferred size. Every field is supplied to the v2 render call.
struct ExtensionTabLayoutContext: Codable, Hashable, Sendable {
    struct ContentSize: Codable, Hashable, Sendable {
        let width: Double
        let height: Double
    }

    let presentation: ExtensionTabPresentation
    let displayID: String?
    let contentSize: ContentSize

    init(presentation: ExtensionTabPresentation, displayID: String?, contentSize: CGSize) {
        self.presentation = presentation
        self.displayID = displayID
        self.contentSize = ContentSize(width: Double(contentSize.width), height: Double(contentSize.height))
    }

    var isValid: Bool {
        contentSize.width.isFinite && contentSize.height.isFinite
            && contentSize.width > 0 && contentSize.height > 0
            && (displayID.map { !$0.isEmpty && $0.utf8.count <= 128 } ?? true)
            && (presentation != .compact
                || (contentSize.width <= Double(NotchWorkspaceLayout.compactContentWidth)
                    && contentSize.height <= Double(NotchWorkspaceLayout.compactContentHeight)))
    }

    private enum CodingKeys: String, CodingKey { case presentation, displayID, contentSize }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(presentation, forKey: .presentation)
        // The JSON contract explicitly distinguishes a missing display from
        // malformed/incomplete context; encode nil as null rather than omit it.
        try values.encode(displayID, forKey: .displayID)
        try values.encode(contentSize, forKey: .contentSize)
    }
}

/// Wire metadata is independent of the plugin's view implementation. Publishing
/// a title or icon change does not replace a mounted content controller.
struct ExtensionTabSnapshot: Decodable {
    let tabs: [ExtensionTabDescriptor]

    func validate() throws {
        guard tabs.count <= 8, Set(tabs.map(\.id)).count == tabs.count else {
            throw ExtensionError.invalidPackage
        }
        try tabs.forEach { try $0.validate() }
    }
}

struct ExtensionTabDescriptor: Decodable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let presentations: [ExtensionTabPresentation]?
    let iconPNG: String?

    init(id: String, title: String, symbol: String, presentations: [ExtensionTabPresentation]? = nil, iconPNG: String? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.presentations = presentations
        self.iconPNG = ExtensionTabIcon.bounded(iconPNG)
    }

    private enum CodingKeys: String, CodingKey { case id, title, symbol, presentations, iconPNG }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        symbol = try values.decode(String.self, forKey: .symbol)
        presentations = values.contains(.presentations)
            ? try values.decode([ExtensionTabPresentation].self, forKey: .presentations) : nil
        // An optional artwork mistake must not remove an otherwise valid tab.
        iconPNG = ExtensionTabIcon.bounded(try? values.decode(String.self, forKey: .iconPNG))
    }

    func supports(_ presentation: ExtensionTabPresentation) -> Bool {
        (presentations ?? [.regular]).contains(presentation)
    }

    func validate() throws {
        let declared = presentations ?? [.regular]
        guard id.utf8.count <= 100,
              id.range(of: #"\A[A-Za-z0-9][A-Za-z0-9._-]*\z"#, options: .regularExpression) != nil,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf8.count <= 64,
              title.rangeOfCharacter(from: .controlCharacters) == nil,
              symbol.utf8.count <= 128,
              !declared.isEmpty, Set(declared).count == declared.count
        else { throw ExtensionError.invalidPackage }
    }

    @MainActor
    var systemSymbol: String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil
            ? "puzzlepiece.extension" : symbol
    }
}

/// Small publisher artwork is decoded once when metadata changes, never in a
/// tab render body. URLs, vector formats, animation and oversized rasters are
/// intentionally outside this optional chrome contract.
enum ExtensionTabIcon {
    static let maximumEncodedBytes = 16_384
    static let maximumPixelDimension = 128

    static func bounded(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= maximumEncodedBytes else { return nil }
        return value
    }

    @MainActor
    static func decode(_ value: String?) -> NSImage? {
        guard let value = bounded(value), let bytes = Data(base64Encoded: value),
              isStaticPNG(bytes),
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == "public.png",
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...maximumPixelDimension).contains(width), (1...maximumPixelDimension).contains(height),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              decoded.width == width, decoded.height == height else { return nil }
        let scale = 16 / CGFloat(max(width, height))
        let image = NSImage(cgImage: decoded, size: NSSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale))
        image.isTemplate = true
        return image
    }

    private static func isStaticPNG(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 33, Array(bytes.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] else { return false }
        func uint32(_ offset: Int) -> Int {
            (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16) | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
        }
        var offset = 8
        var foundHeader = false
        while offset <= bytes.count - 12 {
            let count = uint32(offset)
            guard count <= bytes.count - offset - 12 else { return false }
            let type = Array(bytes[(offset + 4)..<(offset + 8)])
            if !foundHeader {
                guard type == [73, 72, 68, 82], count == 13,
                      (1...maximumPixelDimension).contains(uint32(offset + 8)),
                      (1...maximumPixelDimension).contains(uint32(offset + 12)) else { return false }
                foundHeader = true
            } else if type == [73, 72, 68, 82] { return false }
            if type == [97, 99, 84, 76] { return false } // APNG acTL, including a one-frame animation.
            offset += count + 12
            if type == [73, 69, 78, 68] { return count == 0 && offset == bytes.count }
        }
        return false
    }
}

/// The verified package supplies the provider namespace; plugins supply only a
/// local ID. Identical local IDs from different publishers never alias.
struct ExtensionTabID: Hashable, Sendable {
    let providerID: String
    let localID: String
}
