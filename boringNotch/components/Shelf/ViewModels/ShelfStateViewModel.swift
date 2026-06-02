//
//  ShelfStateViewModel.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-09.

import Foundation
import AppKit

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet { ShelfPersistenceService.shared.save(items) }
    }

    @Published var isLoading: Bool = false

    /// The item showing the transient "Copied" flash, cleared after ~1.2s. Mirrors
    /// IslandNotch's `lastCopiedFileID`.
    @Published var lastCopiedItemID: ShelfItem.ID?
    private var flashClearTask: Task<Void, Never>?

    var isEmpty: Bool { items.isEmpty }

    // Queue for deferred bookmark updates to avoid publishing during view updates
    private var pendingBookmarkUpdates: [ShelfItem.ID: Data] = [:]
    private var updateTask: Task<Void, Never>?

    /// One-shot flag: older builds appended new drops (oldest-leftmost). The shelf now
    /// shows newest-leftmost, so the persisted array is reversed exactly once on first
    /// launch under the new build to bring existing items onto the new invariant.
    private static let newestLeftMigrationKey = "ShelfNewestLeftMigrationV1"

    private init() {
        var loaded = ShelfPersistenceService.shared.load()
        if !UserDefaults.standard.bool(forKey: Self.newestLeftMigrationKey) {
            // Existing items were stored oldest-first; reverse once so the most
            // recently added item sits leftmost, matching new-drop behavior below.
            loaded.reverse()
            UserDefaults.standard.set(true, forKey: Self.newestLeftMigrationKey)
        }
        items = loaded
    }


    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        var merged = items
        // Newest-leftmost invariant: insert each new item at the front (index 0) in
        // iteration order, so within a single multi-file drop the LAST item processed
        // ends up leftmost. A re-dropped item (same identityKey) is PROMOTED to the
        // front — its stale entry is removed first, then re-inserted at 0. Because
        // identityKey is path/content-based, the duplicate references the same backing
        // file, so dropping the old array entry never orphans an on-disk screenshot.
        for it in newItems {
            let key = it.identityKey
            merged.removeAll { $0.identityKey == key }
            merged.insert(it, at: 0)
        }
        items = merged
    }

    func remove(_ item: ShelfItem) {
        item.cleanupStoredData()
        items.removeAll { $0.id == item.id }
    }

    // MARK: - Generic copy + flash

    /// Copies an item to the clipboard in its kind's natural representation and
    /// triggers the "Copied" flash. Screenshots/images use the active agent's
    /// payload mode so a single click produces a paste-ready agent prompt.
    func copyToClipboard(_ item: ShelfItem) {
        let pb = NSPasteboard.general
        switch item.kind {
        case .file:
            if let url = resolveAndUpdateBookmark(for: item) {
                pb.clearContents()
                pb.writeObjects([url as NSURL])
            } else {
                pb.clearContents()
                pb.setString(item.displayName, forType: .string)
            }
        case .text(let string):
            pb.clearContents()
            pb.setString(string, forType: .string)
        case .link(let url):
            pb.clearContents()
            pb.writeObjects([url as NSURL])
        case .screenshot(let meta):
            let agent = ScreenshotPreferences.activeAgent
            PasteboardService.copy(url: Foundation.URL(fileURLWithPath: meta.path),
                                   mode: ScreenshotPreferences.payloadMode(for: agent))
        }
        flashCopied(item.id)
    }

    /// Copies a screenshot/image item as a specific agent payload mode (used by the
    /// right-click "Copy as ▸" submenu).
    func copyToClipboard(_ item: ShelfItem, mode: PayloadMode) {
        guard let url = item.fileURL else { return }
        PasteboardService.copy(url: url, mode: mode)
        flashCopied(item.id)
    }

    /// Sets the "Copied" flash for `id`, auto-clearing after ~1.2s.
    func flashCopied(_ id: ShelfItem.ID) {
        lastCopiedItemID = id
        flashClearTask?.cancel()
        flashClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.lastCopiedItemID == id { self.lastCopiedItemID = nil }
        }
    }

    func updateBookmark(for item: ShelfItem, bookmark: Data) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if case .file = items[idx].kind {
            items[idx].kind = .file(bookmark: bookmark)
        }
    }

    private func scheduleDeferredBookmarkUpdate(for item: ShelfItem, bookmark: Data) {
        pendingBookmarkUpdates[item.id] = bookmark
        
        // Cancel existing task and schedule a new one
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()
            
            guard let self = self else { return }
            
            for (itemID, bookmarkData) in self.pendingBookmarkUpdates {
                if let idx = self.items.firstIndex(where: { $0.id == itemID }),
                   case .file = self.items[idx].kind {
                    self.items[idx].kind = .file(bookmark: bookmarkData)
                }
            }
            
            self.pendingBookmarkUpdates.removeAll()
        }
    }


    func load(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        isLoading = true
        Task { [weak self] in
            let dropped = await ShelfDropService.items(from: providers)
            await MainActor.run {
                self?.add(dropped)
                self?.isLoading = false
            }
        }
    }

    func cleanupInvalidItems() {
        Task { [weak self] in
            guard let self else { return }
            var keep: [ShelfItem] = []
            for item in self.items {
                switch item.kind {
                case .file(let data):
                    let bookmark = Bookmark(data: data)
                    if await bookmark.validate() {
                        keep.append(item)
                    } else {
                        item.cleanupStoredData()
                    }
                default:
                    keep.append(item)
                }
            }
            await MainActor.run { self.items = keep }
        }
    }


    func resolveFileURL(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            scheduleDeferredBookmarkUpdate(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveAndUpdateBookmark(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            updateBookmark(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveFileURLs(for items: [ShelfItem]) -> [URL] {
        var urls: [URL] = []
        for it in items {
            if let u = resolveFileURL(for: it) { urls.append(u) }
        }
        return urls
    }
}
