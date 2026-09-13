//
//  ClipboardItem.swift
//  boringNotch
//
//  Created by Claude on 2026-07-05.
//

import Foundation

enum ClipboardItemKind: String, Codable {
    case text
    case link
    case image
    case fileURL
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let kind: ClipboardItemKind
    var plainText: String?
    /// PNG file name inside the clipboard images directory (images are stored
    /// on disk, not in the JSON history file).
    var imageFileName: String?
    /// Original file URLs as strings; only the paths are re-copied since
    /// sandbox access to the files themselves ends once they leave the pasteboard.
    var fileURLStrings: [String]?
    var sourceAppBundleID: String?
    var pinned: Bool = false

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: ClipboardItemKind,
        plainText: String? = nil,
        imageFileName: String? = nil,
        fileURLStrings: [String]? = nil,
        sourceAppBundleID: String? = nil,
        pinned: Bool = false
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.plainText = plainText
        self.imageFileName = imageFileName
        self.fileURLStrings = fileURLStrings
        self.sourceAppBundleID = sourceAppBundleID
        self.pinned = pinned
    }

    var previewText: String {
        switch kind {
        case .text, .link:
            return plainText ?? ""
        case .image:
            return String(localized: "Image")
        case .fileURL:
            let names = (fileURLStrings ?? [])
                .compactMap { URL(string: $0)?.lastPathComponent }
            return names.isEmpty ? String(localized: "Files") : names.joined(separator: ", ")
        }
    }

    /// Content-based identity used to avoid storing consecutive duplicates.
    var contentFingerprint: String {
        switch kind {
        case .text, .link:
            return "\(kind.rawValue):\(plainText ?? "")"
        case .image:
            return "image:\(imageFileName ?? "")"
        case .fileURL:
            return "files:\((fileURLStrings ?? []).joined(separator: "|"))"
        }
    }
}
