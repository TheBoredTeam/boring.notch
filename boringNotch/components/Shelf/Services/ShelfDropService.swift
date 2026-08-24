//
//  ShelfDropService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
struct ShelfDropService {
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
                return ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
            }
            return nil
        }
        
        if let url = await provider.extractURL() {
            if url.isFileURL {
                if let bookmark = createBookmark(for: url) {
                    return ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
                }
            } else {
                return ShelfItem(kind: .link(url: url), isTemporary: false)
            }
            return nil
        }
        
        if let text = await provider.extractText() {
            return ShelfItem(kind: .text(string: text), isTemporary: false)
        }
        
        if let data = await provider.loadData() {
            if let tempDataURL = await TemporaryFileStorageService.shared.createTempFile(for: .data(data, suggestedName: provider.suggestedName)),
               let bookmark = createBookmark(for: tempDataURL) {
                return ShelfItem(kind: .file(bookmark: bookmark), isTemporary: true)
            }
            return nil
        }
        
        if let fileURL = await provider.extractItem() {
            if let bookmark = createBookmark(for: fileURL) {
                return ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
            }
        }
        
        return nil
    }
    
    private static func createBookmark(for url: URL) -> Data? {
        return (try? Bookmark(url: url))?.data
    }
}
