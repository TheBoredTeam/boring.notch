// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation

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

    init(id: String, title: String, symbol: String, presentations: [ExtensionTabPresentation]? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.presentations = presentations
    }

    private enum CodingKeys: String, CodingKey { case id, title, symbol, presentations }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        symbol = try values.decode(String.self, forKey: .symbol)
        presentations = values.contains(.presentations)
            ? try values.decode([ExtensionTabPresentation].self, forKey: .presentations) : nil
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

/// The verified package supplies the provider namespace; plugins supply only a
/// local ID. Identical local IDs from different publishers never alias.
struct ExtensionTabID: Hashable, Sendable {
    let providerID: String
    let localID: String
}
