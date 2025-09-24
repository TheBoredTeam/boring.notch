import AppKit
import Combine
import Defaults
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private actor ClipboardStore {
    private var db: OpaquePointer?
    private let databaseURL: URL

    init(url: URL) {
        databaseURL = url
        ensureDirectory()
        openDatabase()
        createTablesIfNeeded()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func fetchAll(limit: Int) -> [ClipboardItem] {
        guard let db else { return [] }
        let query = """
        SELECT id, kind, data, preview, createdAt, isFavorite, sourceApp, contentHash
        FROM clipboard_items
        ORDER BY createdAt DESC
        LIMIT ?
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteError("prepare fetchAll")
            return []
        }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var items: [ClipboardItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idCString = sqlite3_column_text(statement, 0),
                let kindCString = sqlite3_column_text(statement, 1),
                let blobPointer = sqlite3_column_blob(statement, 2)
            else { continue }

            let id = UUID(uuidString: String(cString: idCString))
            let kindRaw = String(cString: kindCString)
            let dataSize = Int(sqlite3_column_bytes(statement, 2))
            let blobData = Data(bytes: blobPointer, count: dataSize)
            let preview = String(cString: sqlite3_column_text(statement, 3))
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            let isFavorite = sqlite3_column_int(statement, 5) == 1
            let sourceApp: String?
            if let text = sqlite3_column_text(statement, 6) {
                sourceApp = String(cString: text)
            } else {
                sourceApp = nil
            }
            let hash = String(cString: sqlite3_column_text(statement, 7))

            guard let kind = ClipboardKind(rawValue: kindRaw), let id else { continue }

            let item = ClipboardItem(
                id: id,
                kind: kind,
                data: blobData,
                preview: preview,
                createdAt: createdAt,
                isFavorite: isFavorite,
                sourceApp: sourceApp,
                contentHash: hash
            )
            items.append(item)
        }

        return items
    }

    func upsert(_ item: ClipboardItem) {
        guard let db else { return }
        let sql = """
        INSERT INTO clipboard_items (
            id, kind, data, preview, createdAt, isFavorite, sourceApp, contentHash
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(contentHash) DO UPDATE SET
            id = excluded.id,
            kind = excluded.kind,
            data = excluded.data,
            preview = excluded.preview,
            createdAt = excluded.createdAt,
            sourceApp = excluded.sourceApp,
            isFavorite = CASE WHEN clipboard_items.isFavorite = 1 THEN 1 ELSE excluded.isFavorite END
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteError("prepare upsert")
            return
        }

        bindText(item.id.uuidString, index: 1, statement: statement)
        bindText(item.kind.rawValue, index: 2, statement: statement)
        item.data.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, 3, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
        }
        bindText(item.preview, index: 4, statement: statement)
        sqlite3_bind_double(statement, 5, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 6, item.isFavorite ? 1 : 0)
        if let source = item.sourceApp {
            bindText(source, index: 7, statement: statement)
        } else {
            sqlite3_bind_null(statement, 7)
        }
        bindText(item.contentHash, index: 8, statement: statement)

        if sqlite3_step(statement) != SQLITE_DONE {
            logSQLiteError("execute upsert")
        }
    }

    func delete(ids: [UUID]) {
        guard let db, !ids.isEmpty else { return }
        let sql = "DELETE FROM clipboard_items WHERE id = ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteError("prepare delete")
            return
        }

        for id in ids {
            bindText(id.uuidString, index: 1, statement: statement)
            if sqlite3_step(statement) != SQLITE_DONE {
                logSQLiteError("execute delete")
            }
            sqlite3_reset(statement)
        }
    }

    func setFavorite(id: UUID, value: Bool) {
        guard let db else { return }
        let sql = "UPDATE clipboard_items SET isFavorite = ? WHERE id = ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteError("prepare setFavorite")
            return
        }

        sqlite3_bind_int(statement, 1, value ? 1 : 0)
        bindText(id.uuidString, index: 2, statement: statement)

        if sqlite3_step(statement) != SQLITE_DONE {
            logSQLiteError("execute setFavorite")
        }
    }

    func prune(retentionDays: Int, maxItems: Int) {
        guard let db else { return }

        let threshold = Date().addingTimeInterval(-Double(retentionDays) * 86_400).timeIntervalSince1970
        let deleteOldSQL = "DELETE FROM clipboard_items WHERE createdAt < ? AND isFavorite = 0"

        var deleteOldStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteOldSQL, -1, &deleteOldStatement, nil) == SQLITE_OK {
            sqlite3_bind_double(deleteOldStatement, 1, threshold)
            if sqlite3_step(deleteOldStatement) != SQLITE_DONE {
                logSQLiteError("execute prune old")
            }
        }
        sqlite3_finalize(deleteOldStatement)

        let deleteOverflowSQL = """
        DELETE FROM clipboard_items
        WHERE id IN (
            SELECT id FROM clipboard_items
            WHERE isFavorite = 0
            ORDER BY createdAt DESC
            LIMIT -1 OFFSET ?
        )
        """

        var deleteOverflowStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteOverflowSQL, -1, &deleteOverflowStatement, nil) == SQLITE_OK {
            sqlite3_bind_int(deleteOverflowStatement, 1, Int32(maxItems))
            if sqlite3_step(deleteOverflowStatement) != SQLITE_DONE {
                logSQLiteError("execute prune overflow")
            }
        }
        sqlite3_finalize(deleteOverflowStatement)
    }

    private func ensureDirectory() {
        let folderURL = databaseURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            NSLog("ClipboardStore: Failed to create directory: \(error.localizedDescription)")
        }
    }

    private func openDatabase() {
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            logSQLiteError("open database")
            db = nil
        }
    }

    private func createTablesIfNeeded() {
        guard let db else { return }
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            data BLOB NOT NULL,
            preview TEXT NOT NULL,
            createdAt REAL NOT NULL,
            isFavorite INTEGER NOT NULL DEFAULT 0,
            sourceApp TEXT,
            contentHash TEXT NOT NULL UNIQUE
        )
        """

        if sqlite3_exec(db, createTableSQL, nil, nil, nil) != SQLITE_OK {
            logSQLiteError("create table")
        }

        let createIndexSQL = "CREATE INDEX IF NOT EXISTS idx_clipboard_createdAt ON clipboard_items(createdAt DESC)"
        if sqlite3_exec(db, createIndexSQL, nil, nil, nil) != SQLITE_OK {
            logSQLiteError("create index")
        }

        let createHashIndexSQL = "CREATE UNIQUE INDEX IF NOT EXISTS idx_clipboard_hash ON clipboard_items(contentHash)"
        if sqlite3_exec(db, createHashIndexSQL, nil, nil, nil) != SQLITE_OK {
            logSQLiteError("create hash index")
        }
    }

    private func logSQLiteError(_ context: String) {
        if let db, let errorCString = sqlite3_errmsg(db) {
            let message = String(cString: errorCString)
            NSLog("ClipboardStore: \(context) failed - \(message)")
        }
    }

    private func bindText(_ text: String, index: Int32, statement: OpaquePointer?) {
        text.withCString { cString in
            sqlite3_bind_text(statement, index, cString, -1, SQLITE_TRANSIENT)
        }
    }
}

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var items: [ClipboardItem] = []
    @Published var isMonitoring: Bool = false
    @Published var searchText: String = ""

    private var pollingTimer: Timer?
    private var changeCount = NSPasteboard.general.changeCount
    private var cancellables = Set<AnyCancellable>()
    private let store: ClipboardStore
    private let maxItemSizeBytes = 10 * 1_024 * 1_024

    private init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? documentsDirectory
        let databaseURL = supportDirectory
            .appendingPathComponent("boringNotch", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)
            .appendingPathComponent("clipboard.sqlite")

        store = ClipboardStore(url: databaseURL)

        setupSettingsObservers()

        Task { [weak self] in
            guard let self else { return }
            await self.reloadItems()
            if Defaults[.enableClipboardHistory] {
                self.startMonitoring()
            }
        }
    }

    var filteredItems: [ClipboardItem] {
        let sorted = items.sorted(by: ClipboardManager.sorter)
        guard !searchText.isEmpty else { return sorted }
        let query = searchText.lowercased()
        return sorted.filter { item in
            if item.preview.lowercased().contains(query) { return true }
            if let source = item.sourceApp?.lowercased(), source.contains(query) { return true }
            if item.kind == .text, let string = String(data: item.data, encoding: .utf8)?.lowercased(),
                string.contains(query)
            {
                return true
            }
            return false
        }
    }

    private static func sorter(lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite && !rhs.isFavorite
        }
        return lhs.createdAt > rhs.createdAt
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.checkForChanges()
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func delete(id: UUID) {
        delete(ids: Set([id]))
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.store.delete(ids: Array(ids))
            await self.reloadItems()
        }
    }

    func toggleFavorite(for id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        Task { [weak self] in
            await self?.store.setFavorite(id: id, value: !item.isFavorite)
            await self?.reloadItems()
        }
    }

    func recopyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text, .html:
            if let string = String(data: item.data, encoding: .utf8) {
                pasteboard.setString(string, forType: item.kind == .text ? .string : .html)
            }
        case .rtf:
            pasteboard.setData(item.data, forType: .rtf)
        case .fileURL:
            if let url = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: item.data) as URL? {
                pasteboard.writeObjects([url as NSURL])
            }
        case .image:
            if let image = NSImage(data: item.data) {
                pasteboard.writeObjects([image])
            }
        }
    }

    func clearHistoryKeepingFavorites() {
        Task { [weak self] in
            guard let self else { return }
            let favorites = self.items.filter { $0.isFavorite }.map { $0.id }
            let nonFavorites = Set(self.items.map { $0.id }).subtracting(favorites)
            await self.store.delete(ids: Array(nonFavorites))
            await self.reloadItems()
        }
    }

    private func checkForChanges() {
        guard Defaults[.enableClipboardHistory] else { return }
        let newCount = NSPasteboard.general.changeCount
        guard newCount != changeCount else { return }
        changeCount = newCount
        captureClipboardContent()
    }

    private func captureClipboardContent() {
        guard shouldCaptureCurrentClipboard() else { return }
        guard let item = buildClipboardItem() else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.store.upsert(item)
            await self.store.prune(
                retentionDays: Defaults[.clipboardRetentionDays],
                maxItems: Defaults[.clipboardMaxItems]
            )
            await self.reloadItems()
        }
    }

    private func reloadItems() async {
        let limit = Defaults[.clipboardMaxItems]
        let items = await store.fetchAll(limit: limit)
        self.items = items
    }

    private func buildClipboardItem() -> ClipboardItem? {
        let pasteboard = NSPasteboard.general
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        let now = Date()

        if let string = pasteboard.string(forType: .string),
            let data = string.data(using: .utf8), validateSize(data.count)
        {
            return ClipboardItem(
                kind: .text,
                data: data,
                preview: String(string.prefix(100)),
                createdAt: now,
                isFavorite: false,
                sourceApp: sourceApp
            )
        }

        if Defaults[.clipboardCaptureRichText], let data = pasteboard.data(forType: .rtf), validateSize(data.count) {
            return ClipboardItem(
                kind: .rtf,
                data: data,
                preview: "Rich Text",
                createdAt: now,
                isFavorite: false,
                sourceApp: sourceApp
            )
        }

        if let data = pasteboard.data(forType: .html), validateSize(data.count) {
            return ClipboardItem(
                kind: .html,
                data: data,
                preview: previewFromHTMLData(data),
                createdAt: now,
                isFavorite: false,
                sourceApp: sourceApp
            )
        }

        if Defaults[.clipboardCaptureImages], let image = NSImage(pasteboard: pasteboard) {
            if let data = image.tiffRepresentation, validateSize(data.count) {
                return ClipboardItem(
                    kind: .image,
                    data: data,
                    preview: "Image",
                    createdAt: now,
                    isFavorite: false,
                    sourceApp: sourceApp
                )
            }
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], let url = urls.first {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: url as NSURL, requiringSecureCoding: true),
                validateSize(data.count)
            {
                return ClipboardItem(
                    kind: .fileURL,
                    data: data,
                    preview: url.lastPathComponent,
                    createdAt: now,
                    isFavorite: false,
                    sourceApp: sourceApp
                )
            }
        }

        return nil
    }

    private func shouldCaptureCurrentClipboard() -> Bool {
        guard Defaults[.enableClipboardHistory] else { return false }
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            Defaults[.clipboardExcludedApps].contains(bundleID)
        {
            return false
        }
        return true
    }

    private func validateSize(_ bytes: Int) -> Bool {
        bytes <= maxItemSizeBytes
    }

    private func previewFromHTMLData(_ data: Data) -> String {
        guard let string = String(data: data, encoding: .utf8) else { return "HTML" }
        let stripped = string.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return String(stripped.prefix(100))
    }

    private func setupSettingsObservers() {
        Defaults.publisher(.enableClipboardHistory)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    self.startMonitoring()
                } else {
                    self.stopMonitoring()
                }
            }
            .store(in: &cancellables)

        let retentionPublisher = Defaults.publisher(.clipboardRetentionDays).map { _ in () }
        let maxPublisher = Defaults.publisher(.clipboardMaxItems).map { _ in () }

        retentionPublisher
            .merge(with: maxPublisher)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.store.prune(
                        retentionDays: Defaults[.clipboardRetentionDays],
                        maxItems: Defaults[.clipboardMaxItems]
                    )
                    await self.reloadItems()
                }
            }
            .store(in: &cancellables)
    }
}
