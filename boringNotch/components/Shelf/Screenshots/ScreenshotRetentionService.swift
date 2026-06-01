//
//  ScreenshotRetentionService.swift
//  boringNotch
//
//  Purpose: Optional housekeeping — prune captured screenshots older than N days.
//           Only ever touches `.screenshot` shelf items (and their PNGs); files,
//           text, and links the user dropped are never affected.
//  Layer: Service
//

import Foundation

enum ScreenshotRetentionService {
    /// Removes `.screenshot` items whose capture timestamp is older than the
    /// configured retention window, deleting their backing PNG. No-op when
    /// retention is disabled (0 days).
    @MainActor
    static func runSweep() async {
        let days = ScreenshotPreferences.retentionDays
        guard days > 0 else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        let shelf = ShelfStateViewModel.shared

        let expired = shelf.items.filter { item in
            if case let .screenshot(meta) = item.kind {
                return meta.timestamp < cutoff
            }
            return false
        }

        guard !expired.isEmpty else { return }
        for item in expired {
            // remove(_:) calls cleanupStoredData(), which deletes the PNG (gated to
            // a recognized capture folder) for screenshot items.
            shelf.remove(item)
        }
        Log.store.debug("retention sweep removed \(expired.count) screenshot(s) older than \(days)d")
    }
}
