//
//  ShelfDropService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct ShelfDropService {
    static let supportedContentTypes: [UTType] = [.fileURL, .url, .utf8PlainText, .plainText, .data]

    /// The drag monitor only opens the floating target for content it can identify without
    /// loading providers. Generic data remains accepted once a drop reaches the shelf.
    private static let detectablePasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        NSPasteboard.PasteboardType(UTType.url.identifier),
        .string
    ]

    static func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return false }
        return items.allSatisfy { item in
            item.types.contains { detectablePasteboardTypes.contains($0) }
        }
    }

    static func items(from providers: [NSItemProvider]) async -> [ShelfItem] {
        // Process providers concurrently for better performance with large drops
        await withTaskGroup(of: ShelfItem?.self) { group in
            for provider in providers {
                group.addTask {
                    await processProvider(provider)
                }
            }

            var results: [ShelfItem] = []
            results.reserveCapacity(providers.count)

            for await item in group {
                if let item = item {
                    results.append(item)
                }
            }

            return results
        }
    }

    private static func processProvider(_ provider: NSItemProvider) async -> ShelfItem? {
        if let actualFileURL = await provider.extractFileURL() {
            if let bookmark = createBookmark(for: actualFileURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
            }
            return nil
        }

        if let url = await provider.extractURL() {
            if url.isFileURL {
                if let bookmark = createBookmark(for: url) {
                    return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
                }
            } else {
                return await ShelfItem(kind: .link(url: url), isTemporary: false)
            }
            return nil
        }

        if let text = await provider.extractText() {
            return await ShelfItem(kind: .text(string: text), isTemporary: false)
        }

        if let data = await provider.loadData() {
            if let tempDataURL = await TemporaryFileStorageService.shared.createTempFile(for: .data(data, suggestedName: provider.suggestedName)),
               let bookmark = createBookmark(for: tempDataURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: true)
            }
            return nil
        }

        if let fileURL = await provider.extractItem() {
            if let bookmark = createBookmark(for: fileURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
            }
        }

        return nil
    }

    private static func createBookmark(for url: URL) -> Data? {
        return (try? Bookmark(url: url))?.data
    }
}
