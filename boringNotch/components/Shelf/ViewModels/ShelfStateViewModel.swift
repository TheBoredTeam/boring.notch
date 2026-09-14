import AppKit
import Foundation

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] {
        didSet {
            guard persistenceEnabled else { return }
            schedulePersistence()
        }
    }
    @Published var isLoading = false

    var isEmpty: Bool { items.isEmpty }

    private struct CachedResolution {
        let bookmarkData: Data
        let file: ResolvedShelfFile
    }
    private struct PendingResolution {
        let token: UUID
        let bookmarkData: Data
        let intent: ShelfBookmarkResolutionIntent
        let task: Task<ResolvedShelfFile?, Never>
    }

    private let resolver: ShelfBookmarkResolver
    private let persistenceEnabled: Bool
    private var cachedResolutions: [UUID: CachedResolution] = [:]
    private var pendingResolutions: [UUID: PendingResolution] = [:]
    private var persistenceTask: Task<Void, Never>?
    private let persistenceDelay: Duration = .seconds(1)

    private init() {
        resolver = .live
        persistenceEnabled = true
        items = ShelfPersistenceService.shared.load()
    }

    init(items: [ShelfItem], resolver: ShelfBookmarkResolver) {
        self.items = items
        self.resolver = resolver
        persistenceEnabled = false
    }

    private func schedulePersistence() {
        persistenceTask?.cancel()
        persistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.persistenceDelay ?? .seconds(1))
            guard let self, !Task.isCancelled else { return }
            await ShelfPersistenceService.shared.saveAsync(self.items)
        }
    }

    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        var seen = Set(items.map { $0.identityKey })
        items.append(contentsOf: newItems.filter { seen.insert($0.identityKey).inserted })
    }

    func remove(_ item: ShelfItem) {
        let cachedURL = cachedResolutions[item.id]?.file.url
        let pendingTask = pendingResolutions[item.id]?.task
        cachedResolutions[item.id] = nil
        pendingResolutions[item.id] = nil
        items.removeAll { $0.id == item.id }

        guard item.isTemporary else { return }
        if let cachedURL {
            TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: cachedURL)
        } else if let pendingTask {
            Task {
                if let url = await pendingTask.value?.url {
                    TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: url)
                }
            }
        }
    }

    func resolvedFileURL(for item: ShelfItem) -> URL? {
        resolvedFile(for: item)?.url
    }

    /// Compatibility bridge for synchronous AppKit callbacks. It never resolves a bookmark.
    func resolveAndUpdateBookmark(for item: ShelfItem) -> URL? {
        resolvedFileURL(for: item)
    }

    func resolvedFile(for item: ShelfItem) -> ResolvedShelfFile? {
        guard case .file(let bookmarkData) = currentItem(for: item)?.kind,
              let cached = cachedResolutions[item.id],
              cached.bookmarkData == bookmarkData else {
            return nil
        }
        return cached.file
    }

    func resolveFile(
        for item: ShelfItem,
        intent: ShelfBookmarkResolutionIntent = .presentation,
        refresh: Bool = false
    ) async -> ResolvedShelfFile? {
        guard let bookmarkData = bookmarkData(for: item) else { return nil }
        if let cached = cachedFile(for: item.id, matching: bookmarkData), !refresh {
            return cached
        }

        let pending = pendingResolution(for: item.id, bookmarkData: bookmarkData, intent: intent)
        let file = await pending.task.value
        applyResolution(file, for: item.id, bookmarkData: bookmarkData, token: pending.token)
        return cachedFile(for: item.id, matching: file?.refreshedBookmarkData ?? bookmarkData)
    }

    @discardableResult
    func prefetchFileResolution(for item: ShelfItem) -> UUID? {
        guard let bookmarkData = bookmarkData(for: item) else { return nil }
        if cachedFile(for: item.id, matching: bookmarkData) != nil { return nil }
        let pending = pendingResolution(
            for: item.id,
            bookmarkData: bookmarkData,
            intent: .presentation
        )
        Task { [weak self] in
            let file = await pending.task.value
            self?.applyResolution(file, for: item.id, bookmarkData: bookmarkData, token: pending.token)
        }
        return pending.token
    }

    func invalidatePendingResolution(for itemID: UUID, bookmarkData: Data, token: UUID) {
        guard let pending = pendingResolutions[itemID],
              pending.bookmarkData == bookmarkData,
              pending.token == token else {
            return
        }
        pendingResolutions[itemID] = nil
        pending.task.cancel()
    }

    func updateBookmark(for item: ShelfItem, bookmark: Data) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              case .file = items[index].kind else {
            return
        }
        let current = items[index]
        items[index] = ShelfItem(
            id: current.id,
            kind: .file(bookmark: bookmark),
            isTemporary: current.isTemporary
        )
        cachedResolutions[item.id] = nil
        pendingResolutions[item.id] = nil
    }

    func load(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        isLoading = true
        Task { [weak self] in
            let dropped = await ShelfDropService.items(from: providers)
            self?.add(dropped)
            self?.isLoading = false
        }
    }

    /// Unavailable files remain persisted. This method now warms passive resolution only.
    func cleanupInvalidItems() {
        let snapshot = items
        for item in snapshot {
            if case .file = item.kind { prefetchFileResolution(for: item) }
        }
    }

    func resolveFileURLs(for items: [ShelfItem]) async -> [URL] {
        var urls: [URL] = []
        for item in items {
            if let file = await resolveFile(for: item, intent: .userInitiated, refresh: true) {
                urls.append(file.url)
            }
        }
        return urls
    }

    func flushSync() {
        persistenceTask?.cancel()
        persistenceTask = nil
        ShelfPersistenceService.shared.save(items)
    }

    private func pendingResolution(
        for itemID: UUID,
        bookmarkData: Data,
        intent: ShelfBookmarkResolutionIntent
    ) -> PendingResolution {
        if let pending = pendingResolutions[itemID],
           pending.bookmarkData == bookmarkData,
           pending.intent == intent {
            return pending
        }
        let pending = PendingResolution(
            token: UUID(),
            bookmarkData: bookmarkData,
            intent: intent,
            task: Task { [resolver] in await resolver.resolve(bookmarkData, intent: intent) }
        )
        pendingResolutions[itemID] = pending
        return pending
    }

    private func applyResolution(
        _ file: ResolvedShelfFile?,
        for itemID: UUID,
        bookmarkData: Data,
        token: UUID
    ) {
        guard pendingResolutions[itemID]?.token == token else { return }
        pendingResolutions[itemID] = nil
        guard let file,
              let index = items.firstIndex(where: { $0.id == itemID }),
              case .file(let currentData) = items[index].kind,
              currentData == bookmarkData else {
            return
        }

        let effectiveData = file.refreshedBookmarkData ?? bookmarkData
        if effectiveData != bookmarkData {
            let current = items[index]
            items[index] = ShelfItem(
                id: current.id,
                kind: .file(bookmark: effectiveData),
                isTemporary: current.isTemporary
            )
        }
        cachedResolutions[itemID] = CachedResolution(
            bookmarkData: effectiveData,
            file: file
        )
    }

    private func currentItem(for item: ShelfItem) -> ShelfItem? {
        items.first(where: { $0.id == item.id })
    }

    private func bookmarkData(for item: ShelfItem) -> Data? {
        guard case .file(let data) = currentItem(for: item)?.kind else { return nil }
        return data
    }

    private func cachedFile(for itemID: UUID, matching data: Data) -> ResolvedShelfFile? {
        guard let cached = cachedResolutions[itemID], cached.bookmarkData == data else { return nil }
        return cached.file
    }
}
