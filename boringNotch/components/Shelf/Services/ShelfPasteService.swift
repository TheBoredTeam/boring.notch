//
//  ShelfPasteService.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ShelfPasteService {
    static var canPaste: Bool {
        (NSPasteboard.general.pasteboardItems ?? []).contains(where: supports)
    }

    static func paste() {
        let pasteboardItems = NSPasteboard.general.pasteboardItems ?? []
        guard !pasteboardItems.isEmpty else { return }

        ShelfStateViewModel.shared.isLoading = true
        Task {
            var items: [ShelfItem] = []
            for pasteboardItem in pasteboardItems {
                if let item = await shelfItem(from: pasteboardItem) {
                    items.append(item)
                }
            }
            ShelfStateViewModel.shared.add(items)
            ShelfStateViewModel.shared.isLoading = false
        }
    }

    private static func supports(_ item: NSPasteboardItem) -> Bool {
        if item.availableType(from: [.fileURL, .URL, .png, .tiff, .string]) != nil {
            return true
        }
        if item.types.contains(where: { UTType($0.rawValue)?.conforms(to: .plainText) == true }) {
            return true
        }
        return item.types.contains { type in
            guard !type.rawValue.hasPrefix("com.apple.pasteboard.") else { return false }
            return UTType(type.rawValue)?.preferredFilenameExtension != nil
        }
    }

    private static func shelfItem(from pasteboardItem: NSPasteboardItem) async -> ShelfItem? {
        if let url = fileURL(from: pasteboardItem) {
            return makeFileItem(for: url, isTemporary: false)
        }

        if let url = webURL(from: pasteboardItem) {
            if url.isFileURL {
                return makeFileItem(for: url, isTemporary: false)
            }
            return ShelfItem(kind: .link(url: url))
        }

        if let image = imageData(from: pasteboardItem),
           let url = await writeTemporaryFile(image.data, named: "Pasted Image.\(image.fileExtension)") {
            return makeFileItem(for: url, isTemporary: true)
        }

        if let text = plainText(from: pasteboardItem) {
            return ShelfItem(kind: .text(string: text))
        }

        if let data = genericData(from: pasteboardItem),
           let url = await writeTemporaryFile(data.data, named: "Pasted File.\(data.fileExtension)") {
            return makeFileItem(for: url, isTemporary: true)
        }

        return nil
    }

    private static func fileURL(from item: NSPasteboardItem) -> URL? {
        if let string = item.string(forType: .fileURL),
           let url = URL(string: string), url.isFileURL {
            return url
        }

        guard let plist = item.propertyList(forType: .fileURL) else { return nil }
        if let string = plist as? String,
           let url = URL(string: string), url.isFileURL {
            return url
        }
        if let data = plist as? Data {
            if let string = String(data: data, encoding: .utf8),
               let url = URL(string: string), url.isFileURL {
                return url
            }
            return Bookmark(data: data).resolvedURL
        }
        return nil
    }

    private static func webURL(from item: NSPasteboardItem) -> URL? {
        guard let string = item.string(forType: .URL),
              let url = URL(string: string),
              let scheme = url.scheme,
              !scheme.isEmpty else {
            return nil
        }
        return url
    }

    private static func imageData(from item: NSPasteboardItem) -> (data: Data, fileExtension: String)? {
        if let data = item.data(forType: .png) {
            return (data, "png")
        }
        if let data = item.data(forType: .tiff) {
            return (data, "tiff")
        }
        return nil
    }

    private static func plainText(from item: NSPasteboardItem) -> String? {
        if let text = item.string(forType: .string), !text.isEmpty {
            return text
        }
        for type in item.types where type != .string {
            guard let contentType = UTType(type.rawValue),
                  contentType.conforms(to: .plainText),
                  let text = item.string(forType: type),
                  !text.isEmpty
            else { continue }
            return text
        }
        return nil
    }

    private static func genericData(from item: NSPasteboardItem) -> (data: Data, fileExtension: String)? {
        let handledTypes: Set<NSPasteboard.PasteboardType> = [.fileURL, .URL, .png, .tiff, .string]

        for type in item.types where !handledTypes.contains(type) {
            guard !type.rawValue.hasPrefix("com.apple.pasteboard."),
                  let contentType = UTType(type.rawValue),
                  let fileExtension = contentType.preferredFilenameExtension,
                  let data = item.data(forType: type) else {
                continue
            }
            return (data, fileExtension)
        }

        return nil
    }

    private static func makeFileItem(for url: URL, isTemporary: Bool) -> ShelfItem? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let bookmark = try? Bookmark(url: url) else { return nil }
        return ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: isTemporary)
    }

    private static func writeTemporaryFile(_ data: Data, named name: String) async -> URL? {
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return await TemporaryFileStorageService.shared.createTempFile(
            for: .data(data, suggestedName: name),
            deduplicationKey: "paste-\(digest)"
        )
    }
}
