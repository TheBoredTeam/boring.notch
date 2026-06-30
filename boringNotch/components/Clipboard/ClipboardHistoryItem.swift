//
//  ClipboardHistoryItem.swift
//  boringNotch
//

import Foundation

enum ClipboardHistoryContentKind: String, Codable, CaseIterable, Identifiable {
    case text
    case image

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text:
            return "Text"
        case .image:
            return "Image"
        }
    }

    var systemImage: String {
        switch self {
        case .text:
            return "text.alignleft"
        case .image:
            return "photo"
        }
    }
}

struct ClipboardHistoryItem: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: ClipboardHistoryContentKind
    var createdAt: Date
    var hash: String
    var text: String?
    var imageFilename: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var imageByteCount: Int?
    var sourceAppName: String?
    var sourceBundleIdentifier: String?
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        kind: ClipboardHistoryContentKind,
        createdAt: Date = Date(),
        hash: String,
        text: String? = nil,
        imageFilename: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        imageByteCount: Int? = nil,
        sourceAppName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.hash = hash
        self.text = text
        self.imageFilename = imageFilename
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageByteCount = imageByteCount
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.isPinned = isPinned
    }

    var previewTitle: String {
        switch kind {
        case .text:
            let cleaned = (text ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Empty text" : cleaned
        case .image:
            if let imageWidth, let imageHeight {
                return "Image, \(imageWidth) x \(imageHeight)"
            }
            return "Image"
        }
    }

    var detailText: String {
        switch kind {
        case .text:
            let count = text?.count ?? 0
            return count == 1 ? "1 character" : "\(count) characters"
        case .image:
            let dimensions = imageDimensionsText
            let size = byteCountText
            if let dimensions, let size {
                return "\(dimensions) • \(size)"
            }
            return dimensions ?? size ?? "Image"
        }
    }

    var imageDimensionsText: String? {
        guard let imageWidth, let imageHeight else { return nil }
        return "\(imageWidth) x \(imageHeight)"
    }

    var byteCountText: String? {
        guard let imageByteCount else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(imageByteCount), countStyle: .file)
    }
}

struct ClipboardHistorySection: Identifiable {
    let title: String
    let items: [ClipboardHistoryItem]

    var id: String { title }
}

enum ClipboardHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case images
    case pinned

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "All"
        case .text:
            return "Text"
        case .images:
            return "Images"
        case .pinned:
            return "Pinned"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .text:
            return "text.alignleft"
        case .images:
            return "photo.on.rectangle"
        case .pinned:
            return "pin.fill"
        }
    }
}
