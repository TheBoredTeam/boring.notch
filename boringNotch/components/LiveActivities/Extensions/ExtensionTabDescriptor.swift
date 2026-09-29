// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation

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

    func validate() throws {
        guard id.utf8.count <= 100,
              id.range(of: #"\A[A-Za-z0-9][A-Za-z0-9._-]*\z"#, options: .regularExpression) != nil,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf8.count <= 64,
              title.rangeOfCharacter(from: .controlCharacters) == nil,
              symbol.utf8.count <= 128
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
