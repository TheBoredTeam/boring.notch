//  ScreenshotStore+Delete.swift
//  IslandNotch
//
//  Purpose: Remove a shot from disk and the index.
//  Layer: Service

import Foundation

extension ScreenshotStore {
    /// Deletes one screenshot file and removes its index row.
    func delete(_ entry: ScreenshotEntry) async {
        let folder = folderURL
        let fileURL = entry.url(in: folder)
        try? FileManager.default.removeItem(at: fileURL)

        var index = await indexIO.read(at: indexURL)
        index.entries.removeAll { $0.file == entry.file }
        await indexIO.write(index, to: indexURL)
        setPublishedEntries(index.entries)

        if lastCopiedFileID == entry.id {
            lastCopiedFileID = nil
        }
    }
}
