// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import CryptoKit
import Foundation
import XCTest
@testable import boringNotch

private final class StoreTestURLProtocol: URLProtocol, @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var handler: ((StoreTestURLProtocol) -> Void)?
        var requestCount = 0
    }
    private static let storage = Storage()

    static func configure(_ handler: @escaping (StoreTestURLProtocol) -> Void) {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        storage.handler = handler
        storage.requestCount = 0
    }

    static var requestCount: Int {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.requestCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.storage.lock.lock()
        Self.storage.requestCount += 1
        let handler = Self.storage.handler
        Self.storage.lock.unlock()
        handler?(self)
    }

    override func stopLoading() {}

    func respond(status: Int = 200, headers: [String: String] = [:], chunks: [Data], finish: Bool = true) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        chunks.forEach { client?.urlProtocol(self, didLoad: $0) }
        if finish { client?.urlProtocolDidFinishLoading(self) }
    }
}

final class ExtensionStoreTransferTests: XCTestCase {
    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StoreTestURLProtocol.self]
        return configuration
    }

    private func transfer(maximum: Int = 100, destination: ExtensionStoreTransfer.Destination = .memory,
                          validators: ExtensionStoreTransfer.Validators = .init()) throws -> ExtensionStoreTransfer {
        ExtensionStoreTransfer(url: try XCTUnwrap(URL(string: "https://downloads.example.org/extension.zip")),
                               maximumBytes: maximum, destination: destination, configuration: configuration(), validators: validators)
    }

    func testChunksAreHashedAndWrittenWithoutAccumulatingPackageData() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("extension.zip")
        StoreTestURLProtocol.configure { $0.respond(headers: ["Content-Length": "6"], chunks: [Data("abc".utf8), Data("def".utf8)]) }
        let result = try await transfer(destination: .file(file)).run()
        XCTAssertTrue(result.data.isEmpty)
        XCTAssertEqual(result.byteCount, 6)
        XCTAssertEqual(result.sha256, checksum(Data("abcdef".utf8)))
        XCTAssertEqual(try Data(contentsOf: file), Data("abcdef".utf8))
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testUnknownLengthTransferIsLimitedWhileChunksArrive() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("extension.zip")
        StoreTestURLProtocol.configure { $0.respond(chunks: [Data(repeating: 1, count: 6), Data(repeating: 2, count: 6)]) }
        do {
            _ = try await transfer(maximum: 10, destination: .file(file)).run()
            XCTFail("oversized stream accepted")
        } catch { XCTAssertEqual(error as? ExtensionStoreError, .downloadTooLarge) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testOversizedDeclaredLengthAndHTTPFailureAreRejected() async throws {
        StoreTestURLProtocol.configure { $0.respond(headers: ["Content-Length": "101"], chunks: []) }
        do { _ = try await transfer().run(); XCTFail("oversized declared response accepted") }
        catch { XCTAssertEqual(error as? ExtensionStoreError, .downloadTooLarge) }
        StoreTestURLProtocol.configure { $0.respond(status: 404, chunks: [Data("not found".utf8)]) }
        do { _ = try await transfer().run(); XCTFail("HTTP failure accepted") }
        catch { XCTAssertEqual(error as? ExtensionStoreError, .invalidResponse) }
    }

    func testDecodedResponseDoesNotCompareItsBytesToCompressedLength() async throws {
        StoreTestURLProtocol.configure {
            $0.respond(headers: ["Content-Length": "2", "Content-Encoding": "gzip"], chunks: [Data("decoded".utf8)])
        }
        let result = try await transfer().run()
        XCTAssertEqual(result.data, Data("decoded".utf8))
        XCTAssertEqual(result.byteCount, 7)
    }

    func testConditionalCatalogResponsePreservesValidatorsWithoutContent() async throws {
        StoreTestURLProtocol.configure {
            XCTAssertEqual($0.request.value(forHTTPHeaderField: "If-None-Match"), "\"catalog-1\"")
            XCTAssertEqual($0.request.value(forHTTPHeaderField: "If-Modified-Since"), "Tue, 29 Sep 2026 12:00:00 GMT")
            $0.respond(status: 304, headers: ["ETag": "\"catalog-2\""], chunks: [])
        }
        let validators = ExtensionStoreTransfer.Validators(etag: "\"catalog-1\"", lastModified: "Tue, 29 Sep 2026 12:00:00 GMT")
        let result = try await transfer(validators: validators).run()
        XCTAssertTrue(result.notModified)
        XCTAssertTrue(result.data.isEmpty)
        XCTAssertEqual(result.byteCount, 0)
        XCTAssertEqual(result.validators.etag, "\"catalog-2\"")
        XCTAssertEqual(result.validators.lastModified, validators.lastModified)
    }

    func testUnsolicited304AndPackage304CannotBecomeSuccessfulDownloads() async throws {
        StoreTestURLProtocol.configure {
            XCTAssertNil($0.request.value(forHTTPHeaderField: "If-None-Match"))
            $0.respond(status: 304, chunks: [])
        }
        do { _ = try await transfer().run(); XCTFail("Unsolicited 304 accepted without cached content") }
        catch { XCTAssertEqual(error as? ExtensionStoreError, .invalidResponse) }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("extension.zip")
        do {
            _ = try await transfer(destination: .file(file), validators: .init(etag: "\"v1\"")).run()
            XCTFail("304 accepted for a package download")
        } catch { XCTAssertEqual(error as? ExtensionStoreError, .invalidResponse) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testHTTPValidatorsAreBoundedAndCannotInjectHeaders() async throws {
        StoreTestURLProtocol.configure {
            XCTAssertNil($0.request.value(forHTTPHeaderField: "If-None-Match"))
            XCTAssertNil($0.request.value(forHTTPHeaderField: "If-Modified-Since"))
            $0.respond(headers: ["ETag": String(repeating: "a", count: 1_025),
                                 "Last-Modified": String(repeating: "b", count: 129)], chunks: [Data("ok".utf8)])
        }
        let result = try await transfer(validators: .init(etag: "value\r\nInjected: true", lastModified: "date\n")).run()
        XCTAssertTrue(result.validators.isEmpty)
        XCTAssertFalse(result.notModified)
    }

    func testCancellationRemovesPartialFile() async throws {
        let started = expectation(description: "stream began")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("extension.zip")
        StoreTestURLProtocol.configure { request in
            request.respond(chunks: [Data("partial".utf8)], finish: false)
            started.fulfill()
        }
        let operation = try transfer(destination: .file(file))
        let task = Task { try await operation.run() }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled transfer completed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testExclusiveCreationFailurePreservesUnownedFileAndSymlink() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("existing.zip")
        let link = directory.appendingPathComponent("linked.zip")
        let original = Data("owned by someone else".utf8)
        try original.write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        StoreTestURLProtocol.configure { _ in XCTFail("exclusive creation failure reached network") }
        for destination in [file, link] {
            do { _ = try await transfer(destination: .file(destination)).run(); XCTFail("existing target accepted") }
            catch { XCTAssertTrue(error is CocoaError) }
        }
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), file.path)
    }

    func testCancellationBeforeStartDoesNotLeaveADestination() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("cancelled.zip")
        StoreTestURLProtocol.configure { $0.respond(chunks: [], finish: false) }
        let operation = try transfer(destination: .file(file))
        let task = Task { try await operation.run() }
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled operation completed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testUnsafeInitialURLNeverReachesNetwork() async throws {
        StoreTestURLProtocol.configure { _ in XCTFail("unsafe URL reached the network") }
        let url = try XCTUnwrap(URL(string: "http://downloads.example.org/extension.zip"))
        do {
            _ = try await ExtensionStoreTransfer(url: url, maximumBytes: 100, destination: .memory,
                                                 configuration: configuration()).run()
            XCTFail("HTTP accepted")
        } catch { XCTAssertEqual(error as? ExtensionStoreError, .unsafeURL) }
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 0)
    }

    @MainActor
    func testStoreFetchesOnceUntilManualRefresh() async throws {
        let data = try StoreCatalogFixture.data([StoreCatalogFixture.item(status: "preview", artifact: false)])
        StoreTestURLProtocol.configure { $0.respond(chunks: [data]) }
        let store = ExtensionStore(sessionConfiguration: configuration())
        await store.refresh()
        await store.refresh()
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 1)
        XCTAssertNil(store.errorMessage)
        await store.refresh(force: true)
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 2)
    }

    @MainActor
    func testStoreAutomaticallyRefreshesAfterTTLAndRetriesFailedInitialLoad() async throws {
        let data = try StoreCatalogFixture.data([StoreCatalogFixture.item(status: "preview", artifact: false)])
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        let store = ExtensionStore(sessionConfiguration: configuration(), refreshInterval: 60, now: { date })
        StoreTestURLProtocol.configure { $0.respond(status: 503, chunks: [Data("unavailable".utf8)]) }
        await store.refresh()
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.items.isEmpty)
        StoreTestURLProtocol.configure { $0.respond(chunks: [data]) }
        await store.refresh()
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 1, "An initial failure must remain retryable on Store reopen")
        XCTAssertNil(store.errorMessage)
        date.addTimeInterval(59)
        await store.refresh()
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 1)
        date.addTimeInterval(1)
        await store.refresh()
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 2)
        date.addTimeInterval(-120)
        await store.refresh()
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 3, "A backwards clock must not make freshness indefinite")
    }

    @MainActor
    func testGeneratedJSONSurvivesNativeCacheRecreationAndRevalidatesConditionally() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("catalog-cache.plist")
        let endpoint = try XCTUnwrap(ExtensionCatalog.defaultURL)
        let bytes = try StoreCatalogFixture.data([StoreCatalogFixture.item(status: "preview", artifact: false)])
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        StoreTestURLProtocol.configure {
            XCTAssertEqual($0.request.url, endpoint)
            XCTAssertNil($0.request.value(forHTTPHeaderField: "If-None-Match"))
            $0.respond(headers: ["ETag": "\"v1\"", "Last-Modified": "Tue, 29 Sep 2026 12:00:00 GMT"], chunks: [bytes])
        }
        let first = ExtensionStore(sessionConfiguration: configuration(), catalogURL: endpoint, cacheURL: cache, now: { date })
        await first.refresh()
        XCTAssertEqual(first.items.count, 1)
        XCTAssertNil(first.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        let permissions = try FileManager.default.attributesOfItem(atPath: cache.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        let restored = ExtensionStore(sessionConfiguration: configuration(), catalogURL: endpoint, cacheURL: cache, now: { date })
        XCTAssertEqual(restored.items, first.items)
        await restored.refresh()
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 1, "A fresh cache avoids another request")
        StoreTestURLProtocol.configure {
            XCTAssertEqual($0.request.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
            XCTAssertEqual($0.request.value(forHTTPHeaderField: "If-Modified-Since"), "Tue, 29 Sep 2026 12:00:00 GMT")
            $0.respond(status: 304, headers: ["ETag": "\"v2\""], chunks: [])
        }
        date.addTimeInterval(3_600)
        await restored.refresh()
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 1)
        XCTAssertEqual(restored.items, first.items)
        XCTAssertNil(restored.errorMessage)
        let revalidated = ExtensionStore(sessionConfiguration: configuration(), catalogURL: endpoint, cacheURL: cache, now: { date })
        await revalidated.refresh()
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 1)
        StoreTestURLProtocol.configure {
            XCTAssertEqual($0.request.value(forHTTPHeaderField: "If-None-Match"), "\"v2\"")
            $0.respond(status: 304, chunks: [])
        }
        await revalidated.refresh(force: true)
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 1)
        XCTAssertNil(revalidated.errorMessage)
    }

    @MainActor
    func testMalformedOrFailedRefreshCannotReplaceLastGoodCache() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("catalog-cache.plist")
        let bytes = try StoreCatalogFixture.data([StoreCatalogFixture.item(status: "preview", artifact: false)])
        StoreTestURLProtocol.configure { $0.respond(headers: ["ETag": "\"trusted\""], chunks: [bytes]) }
        let store = ExtensionStore(sessionConfiguration: configuration(), cacheURL: cache)
        await store.refresh()
        let validItems = store.items
        let validCache = try Data(contentsOf: cache)
        StoreTestURLProtocol.configure { $0.respond(headers: ["ETag": "\"invalid\""], chunks: [Data("broken catalog".utf8)]) }
        await store.refresh(force: true)
        XCTAssertEqual(store.items, validItems)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(try Data(contentsOf: cache), validCache)
        StoreTestURLProtocol.configure { $0.respond(status: 503, chunks: [Data("unavailable".utf8)]) }
        await store.refresh(force: true)
        XCTAssertEqual(store.items, validItems)
        XCTAssertEqual(try Data(contentsOf: cache), validCache)
        let restored = ExtensionStore(sessionConfiguration: configuration(), cacheURL: cache)
        XCTAssertEqual(restored.items, validItems)
        StoreTestURLProtocol.configure {
            XCTAssertEqual($0.request.value(forHTTPHeaderField: "If-None-Match"), "\"trusted\"")
            $0.respond(status: 304, chunks: [])
        }
        await restored.refresh(force: true)
        XCTAssertNil(restored.errorMessage)
    }

    @MainActor
    func testRepositoryMigrationDropsOldPlistApprovalsAndRevalidatesNewJSONCache() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("catalog-cache.plist")
        let firstURL = try XCTUnwrap(URL(string: "https://raw.githubusercontent.com/TheBoredTeam/boring.extensions/main/catalog.plist"))
        let secondURL = try XCTUnwrap(ExtensionCatalog.defaultURL)
        let oldBytes = try plistCatalog([StoreCatalogFixture.item()])
        var newItem = StoreCatalogFixture.item(status: "preview", artifact: false)
        newItem["id"] = "org.example.newcatalog"
        newItem["slug"] = "new-catalog"
        let newBytes = try StoreCatalogFixture.data([newItem])
        StoreTestURLProtocol.configure {
            $0.respond(headers: ["ETag": "\"source-one\"", "Last-Modified": "Tue, 29 Sep 2026 12:00:00 GMT"], chunks: [oldBytes])
        }
        let first = ExtensionStore(sessionConfiguration: configuration(), catalogURL: firstURL, cacheURL: cache)
        await first.refresh()
        let oldApprovedItem = try XCTUnwrap(first.items.first)
        XCTAssertNotNil(oldApprovedItem.installableArtifact)
        let second = ExtensionStore(sessionConfiguration: configuration(), catalogURL: secondURL, cacheURL: cache)
        XCTAssertTrue(second.items.isEmpty, "A new catalog source must not inherit another source's approved listings")
        do { _ = try await second.download(oldApprovedItem); XCTFail("Old repository approval survived the source change") }
        catch { XCTAssertEqual(error as? ExtensionStoreError, .unavailable) }
        StoreTestURLProtocol.configure {
            XCTAssertEqual($0.request.url, secondURL)
            XCTAssertNil($0.request.value(forHTTPHeaderField: "If-None-Match"))
            XCTAssertNil($0.request.value(forHTTPHeaderField: "If-Modified-Since"))
            $0.respond(chunks: [newBytes])
        }
        await second.refresh()
        XCTAssertEqual(second.items.map(\.id), ["org.example.newcatalog"])
        XCTAssertNil(second.errorMessage)
        let restored = ExtensionStore(sessionConfiguration: configuration(), catalogURL: secondURL, cacheURL: cache)
        XCTAssertEqual(restored.items, second.items)
        await restored.refresh()
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 1, "The new repository's JSON catalog should restore from the native cache")
        let oldSource = ExtensionStore(sessionConfiguration: configuration(), catalogURL: firstURL, cacheURL: cache)
        XCTAssertTrue(oldSource.items.isEmpty, "Repository binding also applies when reverting the configured source")
        var snapshot = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: cache), options: [], format: nil) as? [String: Any])
        XCTAssertEqual(snapshot["data"] as? Data, newBytes, "Cache serialization must preserve the validated JSON payload")
        snapshot["data"] = Data("corrupted cached catalog".utf8)
        try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0).write(to: cache)
        let corrupt = ExtensionStore(sessionConfiguration: configuration(), catalogURL: secondURL, cacheURL: cache)
        XCTAssertTrue(corrupt.items.isEmpty)
        await corrupt.refresh()
        XCTAssertEqual(corrupt.items.count, 1)
        XCTAssertNil(corrupt.errorMessage)
    }

    @MainActor
    func testOversizedAndSymlinkedCacheFilesAreIgnored() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("catalog-cache.plist")
        try Data(repeating: 0, count: ExtensionCatalog.maximumBytes + 8_193).write(to: cache)
        let oversized = ExtensionStore(sessionConfiguration: configuration(), cacheURL: cache)
        XCTAssertTrue(oversized.items.isEmpty)
        let bytes = try StoreCatalogFixture.data([StoreCatalogFixture.item(status: "preview", artifact: false)])
        StoreTestURLProtocol.configure { $0.respond(chunks: [bytes]) }
        await oversized.refresh()
        XCTAssertEqual(oversized.items.count, 1)
        XCTAssertNil(oversized.errorMessage)
        let link = directory.appendingPathComponent("linked-cache.plist")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: cache)
        let linked = ExtensionStore(sessionConfiguration: configuration(), cacheURL: link)
        XCTAssertTrue(linked.items.isEmpty, "Loading cached approval metadata must not follow symbolic links")
    }

    @MainActor
    func testUnavailableCacheDoesNotPreventValidatedInMemoryCatalog() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try StoreCatalogFixture.data([StoreCatalogFixture.item(status: "preview", artifact: false)])
        StoreTestURLProtocol.configure { $0.respond(chunks: [bytes]) }
        // A directory in place of the cache file deterministically rejects writes.
        let store = ExtensionStore(sessionConfiguration: configuration(), cacheURL: directory)
        await store.refresh()
        XCTAssertEqual(store.items.count, 1)
        XCTAssertNil(store.errorMessage)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    @MainActor
    func testCatalogRemovalInvalidatesStaleInstallAndCachesValidEmptySnapshot() async throws {
        let item = try downloadItem(checksum: String(repeating: "a", count: 64))
        let empty = try StoreCatalogFixture.data([])
        let store = ExtensionStore(items: [item], sessionConfiguration: configuration())
        StoreTestURLProtocol.configure { $0.respond(headers: ["ETag": "\"empty\""], chunks: [empty]) }
        await store.refresh(force: true)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.errorMessage)
        await store.refresh()
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 1, "A valid empty catalog is a successfully loaded catalog")
        do { _ = try await store.download(item); XCTFail("A stale detail view installed a withdrawn listing") }
        catch { XCTAssertEqual(error as? ExtensionStoreError, .unavailable) }
        XCTAssertEqual(StoreTestURLProtocol.requestCount, 1)
    }

    @MainActor
    func testPaidDownloadPreservesExactInstallerRequirementAndCleansUp() async throws {
        let bytes = Data("sample archive payload".utf8)
        let item = try downloadItem(checksum: checksum(bytes), paid: true)
        StoreTestURLProtocol.configure { $0.respond(chunks: [bytes]) }
        let store = ExtensionStore(items: [item], sessionConfiguration: configuration())
        let downloaded = try await store.download(item)
        XCTAssertEqual(downloaded.expected, .init(id: item.id, version: "1.0.0", publisherTeamID: "AB12CD34EF"))
        XCTAssertEqual(try Data(contentsOf: downloaded.url), bytes)
        XCTAssertNil(store.activeDownloadID)
        XCTAssertNil(store.downloadProgress)
        downloaded.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.url.path))
    }

    @MainActor
    func testChecksumMismatchAndUnavailablePreviewNeverReachInstaller() async throws {
        let item = try downloadItem(checksum: String(repeating: "0", count: 64))
        StoreTestURLProtocol.configure { $0.respond(chunks: [Data("wrong payload".utf8)]) }
        let store = ExtensionStore(items: [item], sessionConfiguration: configuration())
        do { _ = try await store.download(item); XCTFail("hash mismatch accepted") }
        catch { XCTAssertEqual(error as? ExtensionStoreError, .checksumMismatch) }
        XCTAssertNil(store.activeDownloadID)
        let preview = try StoreCatalogFixture.decode(StoreCatalogFixture.item(status: "preview"))
        let previewStore = ExtensionStore(items: [preview], sessionConfiguration: configuration())
        let previousRequests = StoreTestURLProtocol.requestCount
        do { _ = try await previewStore.download(preview); XCTFail("preview download accepted") }
        catch { XCTAssertEqual(error as? ExtensionStoreError, .unavailable) }
        XCTAssertEqual(StoreTestURLProtocol.requestCount, previousRequests)
    }

    private func downloadItem(checksum: String, paid: Bool = false) throws -> ExtensionCatalogItem {
        var item = StoreCatalogFixture.item(paid: paid)
        var artifact = try XCTUnwrap(item["artifact"] as? [String: Any])
        artifact["sha256"] = checksum
        item["artifact"] = artifact
        return try StoreCatalogFixture.decode(item)
    }

    private func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func plistCatalog(_ items: [[String: Any]]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["schemaVersion": 1, "extensions": items],
                                           format: .xml, options: 0)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("store-transfer-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }
}
