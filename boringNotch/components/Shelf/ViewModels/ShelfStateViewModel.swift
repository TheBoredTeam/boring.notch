//
//  ShelfStateViewModel.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-09.

import Foundation
import AppKit
import Defaults

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet { ShelfPersistenceService.shared.save(items) }
    }
    @Published private(set) var linkedItems: [ShelfItem] = []

    @Published var isLoading: Bool = false

    var isEmpty: Bool { displayItems.isEmpty }
    var displayItems: [ShelfItem] {
        Defaults[.linkedShelfFolderBookmark] == nil ? items : linkedItems
    }
    var mostRecentHomeItem: ShelfItem? {
        if let linked = linkedItems.first {
            return linked
        }
        return items.last
    }

    private init() {
        items = ShelfPersistenceService.shared.load()
        refreshLinkedItems()
    }


    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        var merged = items
        // Deduplicate by identityKey while preserving order (existing first)
        var seen: Set<String> = Set(merged.map { $0.identityKey })
        for it in newItems {
            let key = it.identityKey
            if !seen.contains(key) {
                merged.append(it)
                seen.insert(key)
            }
        }
        items = merged
    }

    func remove(_ item: ShelfItem) {
        item.cleanupStoredData()
        items.removeAll { $0.id == item.id }
    }

    func updateBookmark(for item: ShelfItem, bookmark: Data) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            guard case .file = items[idx].kind else { return }
            items[idx] = ShelfItem(
                id: items[idx].id,
                kind: .file(bookmark: bookmark),
                isTemporary: items[idx].isTemporary
            )
            return
        }
        if let idx = linkedItems.firstIndex(where: { $0.id == item.id }) {
            guard case .file = linkedItems[idx].kind else { return }
            linkedItems[idx] = ShelfItem(
                id: linkedItems[idx].id,
                kind: .file(bookmark: bookmark),
                isTemporary: linkedItems[idx].isTemporary
            )
        }
    }


    func load(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        isLoading = true
        Task { [weak self] in
            if let linkedBookmark = Defaults[.linkedShelfFolderBookmark] {
                await LinkedFolderShelfService.saveItems(from: providers, to: linkedBookmark)
                await MainActor.run {
                    self?.refreshLinkedItems()
                    self?.isLoading = false
                }
                return
            }

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
            updateBookmark(for: item, bookmark: refreshed)
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

    func refreshLinkedItems() {
        guard let bookmarkData = Defaults[.linkedShelfFolderBookmark] else {
            linkedItems = []
            return
        }
        let limit = min(Defaults[.linkedShelfRecentItemLimit], 4)
        guard limit > 0 else {
            linkedItems = []
            return
        }
        Task { [weak self] in
            let items = await LinkedFolderShelfService.loadItems(from: bookmarkData, limit: limit)
            await MainActor.run { self?.linkedItems = items }
        }
    }

    func isStoredItem(_ item: ShelfItem) -> Bool {
        items.contains(where: { $0.id == item.id })
    }
}
