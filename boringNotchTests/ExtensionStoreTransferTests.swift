// SPDX-License-Identifier: GPL-3.0-only

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

    private func transfer(maximum: Int = 100, destination: ExtensionStoreTransfer.Destination = .memory) throws -> ExtensionStoreTransfer {
        ExtensionStoreTransfer(url: try XCTUnwrap(URL(string: "https://downloads.example.org/extension.zip")),
                               maximumBytes: maximum, destination: destination, configuration: configuration())
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
        let data = try StoreCatalogFixture.data([StoreCatalogFixture.item(artifact: false)])
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

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("store-transfer-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }
}
