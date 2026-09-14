//
//  ClipboardHistoryItem.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import CryptoKit

struct ClipboardSourceApplication {
    let name: String
    let bundleIdentifier: String?
}

struct ClipboardHistoryItem: Identifiable {
    enum Content {
        case text(String, isURL: Bool)
        case image(Data, type: NSPasteboard.PasteboardType, thumbnail: NSImage)

        var data: Data {
            switch self {
            case .text(let value, _): return Data(value.utf8)
            case .image(let data, _, _): return data
            }
        }

        var preview: String {
            switch self {
            case .text(let value, _):
                return value.prefix(240).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            case .image: return "Image"
            }
        }

        var fingerprint: String {
            let kind: String
            switch self {
            case .text: kind = "text:"
            case .image(_, let type, _): kind = type.rawValue + ":"
            }
            return kind + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    let id: UUID
    let content: Content
    let fingerprint: String
    let byteCount: Int
    let source: ClipboardSourceApplication
    let capturedAt: Date

    init(id: UUID = UUID(), content: Content, source: ClipboardSourceApplication, capturedAt: Date = Date()) {
        self.id = id
        self.content = content
        self.fingerprint = content.fingerprint
        self.byteCount = content.data.count
        self.source = source
        self.capturedAt = capturedAt
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if source.name.localizedCaseInsensitiveContains(query)
            || source.bundleIdentifier?.localizedCaseInsensitiveContains(query) == true {
            return true
        }
        switch content {
        case .text(let value, _): return value.localizedCaseInsensitiveContains(query)
        case .image: return "image".localizedCaseInsensitiveContains(query)
        }
    }
}
