// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Combine
import Darwin
import Foundation

/// The caller retains this result until installation completes, then calls cleanup.
/// Download verification supplements the installer's code-signature verification.
struct DownloadedExtension: Sendable {
    let url: URL
    let expected: ExtensionInstallation.Requirement
    fileprivate let temporaryDirectory: URL

    func cleanup() { try? FileManager.default.removeItem(at: temporaryDirectory) }
}

/// A cache belongs to one exact source URL. Its bounded bytes are revalidated
/// before display; a malformed refresh can never replace the last good snapshot.
private enum ExtensionCatalogCache {
    struct Snapshot: Codable {
        let sourceURL: URL
        let data: Data
        let validatedAt: Date
        let validators: ExtensionStoreTransfer.Validators
    }

    static let maximumBytes = ExtensionCatalog.maximumBytes + 8_192
    static var defaultURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BoringNotch/ExtensionStore", isDirectory: true)
            .appendingPathComponent("catalog-v1.plist")
    }

    static func load(from url: URL?, sourceURL: URL?) -> (Snapshot, ExtensionCatalog)? {
        guard let url, url.isFileURL, let sourceURL else { return nil }
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) } ?? -1
        }
        guard descriptor >= 0 else { return nil }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG, metadata.st_size <= maximumBytes,
              let bytes = try? file.read(upToCount: maximumBytes + 1), bytes.count <= maximumBytes,
              let snapshot = try? PropertyListDecoder().decode(Snapshot.self, from: bytes),
              snapshot.sourceURL == sourceURL,
              let catalog = try? ExtensionCatalog.decode(snapshot.data) else { return nil }
        return (snapshot, catalog)
    }

    static func save(_ snapshot: Snapshot, to url: URL?) {
        guard let url, url.isFileURL else { return }
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(snapshot)
            guard data.count <= maximumBytes else { return }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // This is public metadata. A read-only or unavailable cache must
            // not prevent a validated catalog from being used in memory.
        }
    }
}

@MainActor
final class ExtensionStore: ObservableObject {
    static let shared = ExtensionStore(cacheURL: ExtensionCatalogCache.defaultURL)

    @Published private(set) var items: [ExtensionCatalogItem]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var activeDownloadID: String?
    @Published private(set) var downloadProgress: Double?

    private var lastSuccessfulRefresh: Date?
    private var cachedSnapshot: ExtensionCatalogCache.Snapshot?
    private var downloadGeneration: UUID?
    private let sessionConfiguration: URLSessionConfiguration?
    private let catalogURL: URL?
    private let cacheURL: URL?
    private let refreshInterval: TimeInterval
    private let now: () -> Date

    /// Only the shared production store opts into persistence. Tests and previews
    /// inject their endpoint, clock, and cache without touching user state.
    init(items: [ExtensionCatalogItem] = [], sessionConfiguration: URLSessionConfiguration? = nil,
         catalogURL: URL? = ExtensionCatalog.officialURL, cacheURL: URL? = nil,
         refreshInterval: TimeInterval = 3_600, now: @escaping () -> Date = Date.init) {
        self.items = items
        self.sessionConfiguration = sessionConfiguration
        self.catalogURL = catalogURL
        self.cacheURL = cacheURL
        self.refreshInterval = refreshInterval.isFinite ? max(0, refreshInterval) : 3_600
        self.now = now
        if !items.isEmpty {
            lastSuccessfulRefresh = now()
        } else if let (snapshot, catalog) = ExtensionCatalogCache.load(from: cacheURL, sourceURL: catalogURL) {
            self.items = catalog.extensions
            cachedSnapshot = snapshot
            lastSuccessfulRefresh = snapshot.validatedAt
        }
    }

    func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let lastSuccessfulRefresh {
            let age = now().timeIntervalSince(lastSuccessfulRefresh)
            if age >= 0, age < refreshInterval { return }
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let catalogURL, ExtensionCatalogURL.isSafeHTTPS(catalogURL) else { throw ExtensionStoreError.unsafeURL }
            let result = try await ExtensionStoreTransfer(
                url: catalogURL, maximumBytes: ExtensionCatalog.maximumBytes,
                destination: .memory, configuration: sessionConfiguration,
                validators: cachedSnapshot?.validators ?? .init()
            ).run()
            try Task.checkCancellation()
            let data: Data
            if result.notModified {
                guard let cachedSnapshot else { throw ExtensionStoreError.invalidResponse }
                data = cachedSnapshot.data
            } else {
                data = result.data
            }
            let catalog = try ExtensionCatalog.decode(data)
            let snapshot = ExtensionCatalogCache.Snapshot(sourceURL: catalogURL, data: data,
                                                          validatedAt: now(), validators: result.validators)
            ExtensionCatalogCache.save(snapshot, to: cacheURL)
            cachedSnapshot = snapshot
            lastSuccessfulRefresh = snapshot.validatedAt
            items = catalog.extensions
        } catch is CancellationError {
            // A cancelled load does not advance freshness or discard cached data.
        } catch ExtensionStoreError.downloadTooLarge {
            errorMessage = ExtensionStoreError.catalogTooLarge.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func download(_ item: ExtensionCatalogItem) async throws -> DownloadedExtension {
        guard activeDownloadID == nil else { throw ExtensionStoreError.downloadInProgress }
        // A stale detail view cannot install a release removed by a catalog refresh.
        guard items.contains(item), let artifact = item.installableArtifact else {
            throw ExtensionStoreError.unavailable
        }
        try item.validate()
        try Task.checkCancellation()
        let generation = UUID()
        downloadGeneration = generation
        activeDownloadID = item.id
        downloadProgress = nil
        defer { activeDownloadID = nil; downloadProgress = nil; downloadGeneration = nil }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "boring-notch-store-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        var keepDownload = false
        defer { if !keepDownload { try? FileManager.default.removeItem(at: directory) } }
        let url = directory.appendingPathComponent("extension.zip")
        let result = try await ExtensionStoreTransfer(
            url: artifact.url, maximumBytes: ExtensionPackage.maximumBytes,
            destination: .file(url), configuration: sessionConfiguration
        ) { [weak self] progress in
            Task { @MainActor in
                guard self?.downloadGeneration == generation else { return }
                self?.downloadProgress = progress
            }
        }.run()
        try Task.checkCancellation()
        guard result.byteCount > 0 else { throw ExtensionStoreError.emptyDownload }
        guard result.sha256 == artifact.sha256.lowercased() else { throw ExtensionStoreError.checksumMismatch }
        guard items.contains(item) else { throw ExtensionStoreError.unavailable }
        keepDownload = true
        return DownloadedExtension(url: url, expected: .init(
            id: item.id, version: artifact.version, publisherTeamID: artifact.publisherTeamID
        ), temporaryDirectory: directory)
    }
}
