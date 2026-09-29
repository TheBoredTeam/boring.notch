// SPDX-License-Identifier: GPL-3.0-only

import Combine
import Foundation

/// The caller retains this result until installation completes, then calls cleanup.
/// Download verification supplements the installer's code-signature verification.
struct DownloadedExtension: Sendable {
    let url: URL
    let expected: ExtensionInstallation.Requirement
    fileprivate let temporaryDirectory: URL

    func cleanup() { try? FileManager.default.removeItem(at: temporaryDirectory) }
}

@MainActor
final class ExtensionStore: ObservableObject {
    static let shared = ExtensionStore()

    @Published private(set) var items: [ExtensionCatalogItem]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var activeDownloadID: String?
    @Published private(set) var downloadProgress: Double?

    private var hasLoaded: Bool
    private var downloadGeneration: UUID?
    private let sessionConfiguration: URLSessionConfiguration?

    /// Prefilled entries provide a native preview/test seam without changing the
    /// production catalog URL. Production starts empty and loads on Store entry.
    init(items: [ExtensionCatalogItem] = [], sessionConfiguration: URLSessionConfiguration? = nil) {
        self.items = items
        hasLoaded = !items.isEmpty
        self.sessionConfiguration = sessionConfiguration
    }

    func refresh(force: Bool = false) async {
        guard !isLoading, force || !hasLoaded else { return }
        isLoading = true
        hasLoaded = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let catalogURL = ExtensionCatalog.officialURL else { throw ExtensionStoreError.unsafeURL }
            let result = try await ExtensionStoreTransfer(
                url: catalogURL, maximumBytes: ExtensionCatalog.maximumBytes,
                destination: .memory, configuration: sessionConfiguration
            ).run()
            try Task.checkCancellation()
            items = try ExtensionCatalog.decode(result.data).extensions
        } catch is CancellationError {
            // A cancelled initial load may be retried when the Store is reopened.
            hasLoaded = !items.isEmpty
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
