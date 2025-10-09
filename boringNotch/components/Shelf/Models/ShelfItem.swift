//
//  ShelfItem.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import AppKit
import Foundation

enum ShelfItemKind: Codable, Equatable, Sendable {
    case file(bookmark: Data)
    case text(string: String)
    case link(url: URL)

    enum CodingKeys: String, CodingKey { case type, value }

    enum KindTag: String, Codable { case file, text, link }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindTag.self, forKey: .type)
        switch type {
        case .file:
            let data = try container.decode(Data.self, forKey: .value)
            self = .file(bookmark: data)
        case .text:
            self = .text(string: try container.decode(String.self, forKey: .value))
        case .link:
            self = .link(url: try container.decode(URL.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .file(let bookmark):
            try container.encode(KindTag.file, forKey: .type)
            try container.encode(bookmark, forKey: .value)
        case .text(let string):
            try container.encode(KindTag.text, forKey: .type)
            try container.encode(string, forKey: .value)
        case .link(let url):
            try container.encode(KindTag.link, forKey: .type)
            try container.encode(url, forKey: .value)
        }
    }

}

@MainActor
struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: ShelfItemKind
    var isTemporary: Bool
    init(id: UUID = UUID(), kind: ShelfItemKind, isTemporary: Bool = false) {
        self.id = id
        self.kind = kind
        self.isTemporary = isTemporary
    }
    
    var displayName: String {
        switch kind {
        case .file(let bookmarkData):
            let bookmark = Bookmark(data: bookmarkData)
            guard let resolvedURL = bookmark.resolveURL() else { return "" }
            
            // Check for stored data files (text blocks, weblocs, etc.) to provide friendly names
            if resolvedURL.pathExtension.lowercased() == "json" && resolvedURL.path.contains("TextBlocks") {
                do {
                    let data = try Data(contentsOf: resolvedURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    struct TextBlockData: Codable {
                        let content: String
                        let title: String?
                        var displayTitle: String {
                            if let title = title, !title.isEmpty {
                                return title
                            }
                            let firstLine = content.components(separatedBy: .newlines).first ?? content
                            if firstLine.count > 50 {
                                return String(firstLine.prefix(47)) + "..."
                            }
                            return firstLine
                        }
                    }
                    if let textData = try? decoder.decode(TextBlockData.self, from: data) {
                        return textData.displayTitle
                    }
                } catch {
                    // Fall through to default naming
                }
            } else if resolvedURL.pathExtension.lowercased() == "webloc" && resolvedURL.path.contains("WebLocs") {
                do {
                    let data = try Data(contentsOf: resolvedURL)
                    if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                       let urlString = plist["URL"] as? String {
                        let title = plist["Title"] as? String
                        return title ?? urlString
                    }
                } catch {
                    // Fall through to default naming
                }
            }
            return (try? resolvedURL.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? resolvedURL.lastPathComponent
        case .text(let string):
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case .link(let url):
            let s = url.absoluteString
            if s.hasPrefix("https://") {
                return String(s.dropFirst("https://".count))
            } else if s.hasPrefix("http://") {
                return String(s.dropFirst("http://".count))
            } else {
                return s
            }
        }
    }
    
    var fileURL: URL? {
        guard case .file = kind else { return nil }
        return ShelfStateViewModel.shared.resolveFileURL(for: self)
    }
    
    var URL: URL? {
        if case let .file(bookmark) = kind { return resolvedContext(for: bookmark)?.url }
        else if case let .link(url) = kind { return url }
        else { return nil }
    }
    
    var icon: NSImage {
        guard case .file = kind else {
            return Self.thumbnailSymbolImage(systemName: kind.iconSymbolName) ?? NSImage()
        }
        if let resolvedURL = ShelfStateViewModel.shared.resolveFileURL(for: self) {
            return NSWorkspace.shared.icon(forFile: resolvedURL.path)
        }
        return NSImage()
    }
    

    func cleanupStoredData() {
        guard case let .file(bookmark) = kind,
              let context = resolvedContext(for: bookmark) else { return }
        
        let url = context.url
        
        // Handle temporary files
        if isTemporary {
            TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: url)
            return
        }
    }
}

private extension ShelfItem {
   static func thumbnailSymbolImage(
        systemName: String,
    size: CGSize = CGSize(width: 64, height: 80), 
    symbolPointSize: CGFloat = 38,
    backgroundColor: NSColor = NSColor.white,
    symbolColor: NSColor = NSColor.labelColor
    ) -> NSImage? {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = CGRect(origin: .zero, size: size)
        let cornerRadius = min(size.width, size.height) * 0.06
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: cornerRadius, yRadius: cornerRadius)
        backgroundColor.setFill()
        path.fill()

        if let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
            let symbolSize = CGSize(width: symbolPointSize, height: symbolPointSize)
            let symbolOrigin = CGPoint(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2
            )
            let symbolRect = CGRect(origin: symbolOrigin, size: symbolSize)
            symbol.draw(in: symbolRect)
        }

        return image
    }
}

// MARK: - Identity key for deduplication
extension ShelfItem {
    var identityKey: String {
        switch kind {
        case .file(let bookmark):
            if let url = resolvedContext(for: bookmark)?.url {
                return "file://" + url.standardizedFileURL.path
            }
            return "file://missing/" + bookmark.base64EncodedString()
        case .link(let u):
            return "link://" + u.absoluteString
        case .text(let s):
            return "text://" + s
        }
    }
}

// MARK: - Private helpers
private extension ShelfItemKind {
    var iconSymbolName: String {
        switch self {
        case .file:
            return "questionmark.circle"
        case .text:
            return "text.justifyleft"
        case .link:
            return "link"
        }
    }
}

private extension ShelfItem {
    func resolvedContext(for bookmarkData: Data) -> (url: URL, bookmark: Data)? {
        let bookmark = Bookmark(data: bookmarkData)
        if let url = bookmark.resolveURL() {
            return (url, bookmark.refreshedData ?? bookmarkData)
        }
        return nil
    }
}
