//
//  ClipboardStore.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import Foundation

/// Owns the clipboard history array and everything that mutates it.
///
/// Newest-first, unlike `ShelfStateViewModel` which appends. Duplicates move to the front and
/// have their timestamp refreshed rather than being skipped: re-copying something from an hour
/// ago should surface it.
@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published private(set) var items: [ClipboardItem] = [] {
        didSet { ClipboardPersistenceService.shared.scheduleSave(items) }
    }

    var isEmpty: Bool { items.isEmpty }

    private var limitCancellable: AnyCancellable?

    private init() {
        // This does schedule one redundant save of what was just loaded; it is debounced and
        // off-main, and matching `ShelfStateViewModel`'s shape is worth more than avoiding it.
        items = ClipboardPersistenceService.shared.load()

        // Lowering the limit in Settings should take effect at once, not on the next copy.
        limitCancellable = Defaults.publisher(.clipboardHistoryLimit)
            .sink { [weak self] _ in
                Task { @MainActor in self?.trimToLimit() }
            }
    }

    // MARK: - Mutation

    func insert(_ item: ClipboardItem) {
        if let existing = items.firstIndex(where: { $0.identityKey == item.identityKey }) {
            // Already known: refresh and move to front. Do not keep the incoming blob — the
            // stored one is identical, and writing it would leak a file per re-copy.
            if case .image(let incoming) = item.kind,
               case .image(let stored) = items[existing].kind,
               incoming.fileName != stored.fileName {
                ClipboardBlobStore.shared.delete(incoming)
            }
            var moved = items.remove(at: existing)
            moved.createdAt = item.createdAt
            moved.sourceBundleID = item.sourceBundleID
            items.insert(moved, at: 0)
            return
        }

        items.insert(item, at: 0)
        trimToLimit()
    }

    func remove(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: index)
        deleteBlobs(for: [removed])
    }

    func clearAll() {
        let removed = items
        items = []
        deleteBlobs(for: removed)
        Task.detached(priority: .background) {
            ClipboardBlobStore.shared.garbageCollect(keeping: [])
        }
    }

    private func trimToLimit() {
        let limit = max(1, Defaults[.clipboardHistoryLimit])
        guard items.count > limit else { return }
        let evicted = Array(items[limit...])
        items = Array(items.prefix(limit))
        deleteBlobs(for: evicted)
    }

    private func deleteBlobs(for evicted: [ClipboardItem]) {
        guard !evicted.isEmpty else { return }
        Task.detached(priority: .utility) {
            for item in evicted {
                ClipboardBlobStore.shared.deleteBlobs(of: item)
            }
        }
    }

    // MARK: - Launch housekeeping

    /// Reclaims blob files the history no longer references. Cheap, and the only recovery path
    /// for a crash between trimming and deletion.
    func collectGarbage() {
        let referenced = items.referencedBlobFileNames
        Task.detached(priority: .background) {
            ClipboardBlobStore.shared.garbageCollect(keeping: referenced)
        }
    }
}

// MARK: - Thumbnails

/// Memory cache for card artwork, mirroring `ThumbnailService`'s coalescing so a fast scroll
/// cannot kick off duplicate loads for the same item.
actor ClipboardThumbnailCache {
    static let shared = ClipboardThumbnailCache()

    private var cache: [UUID: NSImage] = [:]
    private var pending: [UUID: Task<NSImage?, Never>] = [:]

    private init() {}

    func thumbnail(for item: ClipboardItem) async -> NSImage? {
        if let cached = cache[item.id] { return cached }
        if let inflight = pending[item.id] { return await inflight.value }

        let task = Task<NSImage?, Never> { [kind = item.kind] in
            await Self.render(kind)
        }
        pending[item.id] = task

        let image = await task.value
        pending[item.id] = nil
        if let image { cache[item.id] = image }
        return image
    }

    func evict(_ id: UUID) {
        cache[id] = nil
        pending[id]?.cancel()
        pending[id] = nil
    }

    func clear() {
        cache.removeAll()
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
    }

    private static func render(_ kind: ClipboardItemKind) async -> NSImage? {
        switch kind {
        case .image(let ref):
            // Prefer the thumbnail blob; fall back to the full image if it was never written.
            let name = ref.thumbFileName ?? ref.fileName
            let url = ClipboardBlobStore.shared.url(forFileName: name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)

        case .files(let refs):
            guard let first = refs.first else { return nil }
            // A resolvable bookmark buys a real QuickLook preview; otherwise the workspace icon,
            // which is UTI-driven and needs no read access.
            if let bookmarkData = first.bookmark {
                let bookmark = Bookmark(data: bookmarkData)
                if let url = bookmark.resolveURL(),
                   let preview = await ThumbnailService.shared.thumbnail(
                        for: url, size: CGSize(width: 56, height: 56)) {
                    return preview
                }
            }
            return NSWorkspace.shared.icon(forFile: first.path)

        case .text, .link:
            return nil
        }
    }
}
