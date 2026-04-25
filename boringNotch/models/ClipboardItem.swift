//
//  ClipboardItem.swift
//  boringNotch
//
//  Created by boringNotch contributors on 2026-04-19.
//

import AppKit
import Foundation

enum ClipboardItemType: String, Codable {
    case text
    case image
    case fileURL
}

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let type: ClipboardItemType
    let timestamp: Date
    let sourceAppBundleID: String?
    var isPinned: Bool

    // Content storage
    let textContent: String?
    let imageContent: NSImage?
    let fileURL: URL?

    var displayText: String {
        switch type {
        case .text:
            return textContent ?? ""
        case .image:
            return "Image"
        case .fileURL:
            return fileURL?.lastPathComponent ?? "File"
        }
    }

    var sourceAppIcon: NSImage? {
        guard let bundleID = sourceAppBundleID,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    var sourceAppName: String? {
        guard let bundleID = sourceAppBundleID,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return FileManager.default.displayName(atPath: appURL.path)
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }

    static func fromPasteboard(_ pasteboard: NSPasteboard, bundleID: String?) -> ClipboardItem? {
        if let fileURLData = pasteboard.data(forType: .fileURL),
           let url = URL(dataRepresentation: fileURLData, relativeTo: nil)
        {
            return ClipboardItem(
                id: UUID(), type: .fileURL, timestamp: Date(),
                sourceAppBundleID: bundleID, isPinned: false,
                textContent: nil, imageContent: nil, fileURL: url
            )
        }

        if let image = NSImage(pasteboard: pasteboard), image.size.width > 0 {
            return ClipboardItem(
                id: UUID(), type: .image, timestamp: Date(),
                sourceAppBundleID: bundleID, isPinned: false,
                textContent: nil, imageContent: image, fileURL: nil
            )
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return ClipboardItem(
                id: UUID(), type: .text, timestamp: Date(),
                sourceAppBundleID: bundleID, isPinned: false,
                textContent: text, imageContent: nil, fileURL: nil
            )
        }

        return nil
    }
}
