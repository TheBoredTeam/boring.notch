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
    static func items(from providers: [NSItemProvider]) async -> [ShelfItem] {
        var results: [ShelfItem] = []

        for provider in providers {
            if let actualFileURL = await provider.extractFileURL() {
                if let bookmark = await createBookmark(for: actualFileURL) {
                    await results.append(ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false))
                }
                continue
            } else if let url = await provider.extractURL() {
                await results.append(ShelfItem(kind: .link(url: url), isTemporary: false))
                continue
            } else if let text = await provider.extractText() {
                await results.append(ShelfItem(kind: .text(string: text), isTemporary: false))
                continue
            } else if let data = await provider.loadData() {
                if let tempDataURL = await TemporaryFileStorageService.shared.createTempFile(for: .data(data, suggestedName: provider.suggestedName)),
                   let bookmark = await createBookmark(for: tempDataURL) {
                    await results.append(ShelfItem(kind: .file(bookmark: bookmark), isTemporary: true))
                }
                continue
            } else if let fileURL = await provider.extractItem() {
                if let bookmark = await createBookmark(for: fileURL) {
                    await results.append(ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false))
                }
            }
        }

        return results
    }
    
    private static func createBookmark(for url: URL) async -> Data? {
    return (try? Bookmark(url: url))?.data
    }
}

