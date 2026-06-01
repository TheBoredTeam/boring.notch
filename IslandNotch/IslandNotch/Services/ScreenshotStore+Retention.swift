//  ScreenshotStore+Retention.swift
//  IslandNotch
//
//  Purpose: Optional housekeeping — delete shots older than N days so the folder
//           doesn't grow without bound. 0 days = never.
//  Layer: Service

import Foundation

extension ScreenshotStore {
    /// Deletes PNGs older than `preferences.retentionDays` and prunes their index
    /// rows. No-op when retention is disabled (0).
    func runRetentionSweep() async {
        let days = preferences.retentionDays
        guard days > 0 else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        let folder = folderURL
        let index = await indexIO.read(at: indexURL)
        let fm = FileManager.default

        var kept: [ScreenshotEntry] = []
        var deletedCount = 0
        for entry in index.entries {
            if entry.ts < cutoff {
                try? fm.removeItem(at: entry.url(in: folder))
                deletedCount += 1
            } else {
                kept.append(entry)
            }
        }

        if deletedCount > 0 {
            await persist(entries: kept)
            Log.store.debug("retention sweep deleted \(deletedCount) shot(s) older than \(days)d")
        }
    }
}
