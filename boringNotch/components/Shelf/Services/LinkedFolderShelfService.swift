//
//  LinkedFolderShelfService.swift
//  boringNotch
//
//  Created by Codex on 2025-10-11.
//

import Foundation

enum LinkedFolderShelfService {
    static func loadItems(from bookmarkData: Data, limit: Int) async -> [ShelfItem] {
        guard limit > 0 else { return [] }

        let bookmark = Bookmark(data: bookmarkData)
        guard let folderURL = bookmark.resolveURL() else { return [] }

        return await folderURL.accessSecurityScopedResource { accessibleURL in
            let keys: Set<URLResourceKey> = [
                .contentModificationDateKey,
                .creationDateKey,
                .isDirectoryKey
            ]
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]

            let urls = (try? FileManager.default.contentsOfDirectory(
                at: accessibleURL,
                includingPropertiesForKeys: Array(keys),
                options: options
            )) ?? []

            let sorted = urls.sorted { lhs, rhs in
                let lhsDate = resourceDate(for: lhs)
                let rhsDate = resourceDate(for: rhs)
                if lhsDate == rhsDate {
                    return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
                }
                return lhsDate > rhsDate
            }

            var results: [ShelfItem] = []
            results.reserveCapacity(min(sorted.count, limit))

            for url in sorted.prefix(limit) {
                if let bookmark = try? Bookmark(url: url) {
                    let item = await ShelfItem(kind: .file(bookmark: bookmark.data))
                    results.append(item)
                }
            }

            return results
        }
    }

    private static func resourceDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.contentModificationDate ?? values?.creationDate ?? Date.distantPast
    }
}
