//
//  ClipboardItem.swift
//  boringNotch
//
//  Created on 2026-04-13.
//

import AppKit
import Foundation

enum ClipboardItemKind: Equatable {
    case text(String)
    case image(NSImage)
    case fileURL(URL)

    static func == (lhs: ClipboardItemKind, rhs: ClipboardItemKind) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)):
            return a == b
        case (.fileURL(let a), .fileURL(let b)):
            return a == b
        case (.image, .image):
            return false
        default:
            return false
        }
    }
}

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID = UUID()
    let kind: ClipboardItemKind
    let timestamp: Date

    var preview: String {
        switch kind {
        case .text(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 80 {
                return String(trimmed.prefix(80)) + "..."
            }
            return trimmed
        case .image:
            return "Image"
        case .fileURL(let url):
            return url.lastPathComponent
        }
    }

    var icon: String {
        switch kind {
        case .text:
            return "doc.plaintext"
        case .image:
            return "photo"
        case .fileURL:
            return "doc"
        }
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}
