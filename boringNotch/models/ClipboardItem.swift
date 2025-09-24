import Foundation
import CryptoKit

enum ClipboardKind: String, Codable, CaseIterable {
    case text
    case image
    case fileURL
    case rtf
    case html
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipboardKind
    var data: Data
    var preview: String
    let createdAt: Date
    var isFavorite: Bool
    var sourceApp: String?
    var contentHash: String

    init(
        id: UUID = UUID(),
        kind: ClipboardKind,
        data: Data,
        preview: String? = nil,
        createdAt: Date = Date(),
        isFavorite: Bool = false,
        sourceApp: String? = nil,
        contentHash: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.data = data
        self.preview = preview ?? ClipboardItem.previewText(for: kind, data: data)
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.sourceApp = sourceApp
        self.contentHash = contentHash ?? ClipboardItem.hash(of: data)
    }

    static func previewText(for kind: ClipboardKind, data: Data) -> String {
        switch kind {
        case .text, .html:
            if let string = String(data: data, encoding: .utf8) {
                return String(string.prefix(100))
            }
            return ""
        case .fileURL:
            if let nsURL = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data),
                let url = nsURL as URL?
            {
                return url.lastPathComponent
            }
            return "File"
        case .image:
            return "Image"
        case .rtf:
            return "Rich Text"
        }
    }

    static func hash(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
