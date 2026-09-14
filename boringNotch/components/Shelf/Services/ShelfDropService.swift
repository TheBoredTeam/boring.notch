//
//  ShelfDropService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-26.
//

import AppKit
import Foundation

struct ShelfDropService {
    static func items(
        from providers: [NSItemProvider],
        decoder: ShelfTransferDecoder = ShelfTransferDecoder()
    ) async -> [ShelfItem] {
        let batch = await decoder.decode(providers)
        defer { batch.resources.release() }

        var items: [ShelfItem] = []
        items.reserveCapacity(batch.values.count)
        for value in batch.values {
            switch value {
            case .file(let file):
                guard let bookmark = createBookmark(for: file.url) else { continue }
                if file.isOwnedTemporary {
                    batch.resources.relinquishOwnedTemporaryFile(file.url)
                }
                items.append(
                    await ShelfItem(
                        kind: .file(bookmark: bookmark),
                        isTemporary: file.isOwnedTemporary
                    )
                )
            case .link(let url):
                items.append(await ShelfItem(kind: .link(url: url)))
            case .text(let text):
                items.append(await ShelfItem(kind: .text(string: text)))
            }
        }
        return items
    }
    
    private static func createBookmark(for url: URL) -> Data? {
        (try? Bookmark(url: url))?.data
    }
}
