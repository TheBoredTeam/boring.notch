import XCTest
@testable import boringNotch

private final class BlockingShelfResolution: @unchecked Sendable {
    private let lock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private var invocations = 0
    private let result: ResolvedShelfFile?

    init(result: ResolvedShelfFile? = nil) {
        self.result = result
    }

    func resolve(_: Data, _: ShelfBookmarkResolutionIntent) -> ResolvedShelfFile? {
        lock.lock()
        invocations += 1
        lock.unlock()
        started.signal()
        release.wait()
        return result
    }

    func waitUntilStarted(timeout: TimeInterval = 1) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: self.started.wait(timeout: .now() + timeout) == .success)
            }
        }
    }

    func unblock(count: Int = 1) {
        for _ in 0..<count { release.signal() }
    }

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocations
    }
}

private final class SequencedShelfResolution: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [ResolvedShelfFile?]
    private(set) var intents: [ShelfBookmarkResolutionIntent] = []

    init(_ results: [ResolvedShelfFile?]) {
        self.results = results
    }

    func resolve(_: Data, _ intent: ShelfBookmarkResolutionIntent) -> ResolvedShelfFile? {
        lock.lock()
        defer { lock.unlock() }
        intents.append(intent)
        return results.isEmpty ? nil : results.removeFirst()
    }
}

final class ShelfFileResolutionTests: XCTestCase {
    @MainActor
    func testPersistenceRoundTripKeepsIDAndBookmarkData() throws {
        let item = ShelfItem(
            id: UUID(),
            kind: .file(bookmark: Data("persisted".utf8)),
            isTemporary: true
        )
        let decoded = try JSONDecoder().decode(
            ShelfItem.self,
            from: JSONEncoder().encode(item)
        )
        XCTAssertEqual(decoded, item)
    }

    func testBlockedResolutionDoesNotBlockMainActorAndReusesInflightWork() async {
        let blocking = BlockingShelfResolution()
        let resolver = ShelfBookmarkResolver(resolution: blocking.resolve)
        let data = Data("blocked-volume".utf8)

        let first = Task { await resolver.resolve(data) }
        let didStart = await blocking.waitUntilStarted()
        XCTAssertTrue(didStart)
        let second = Task { await resolver.resolve(data) }

        let mainActorResponded = expectation(description: "main actor remains responsive")
        Task { @MainActor in mainActorResponded.fulfill() }
        await fulfillment(of: [mainActorResponded], timeout: 0.2)

        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(blocking.invocationCount, 1)
        blocking.unblock()
        _ = await first.value
        _ = await second.value
        XCTAssertEqual(blocking.invocationCount, 1)
    }

    func testTimeoutAndLateCompletionUseCurrentGeneration() {
        let file = ResolvedShelfFile(
            url: URL(fileURLWithPath: "/tmp/late"),
            refreshedBookmarkData: nil,
            displayName: "late",
            isDirectory: false,
            contentTypeIdentifier: nil
        )
        var state = ShelfFileResolutionState()
        let first = state.begin()
        XCTAssertTrue(state.timeOut(generation: first))
        let retry = state.begin()
        XCTAssertFalse(state.finish(file, generation: first))
        XCTAssertEqual(state.phase, .loading)
        XCTAssertTrue(state.finish(file, generation: retry))
        XCTAssertEqual(state.phase, .available(file))
    }

    @MainActor
    func testLateCompletionAfterRemovalIsIgnored() async {
        let data = Data("removed".utf8)
        let item = ShelfItem(kind: .file(bookmark: data))
        let file = ResolvedShelfFile(
            url: URL(fileURLWithPath: "/tmp/removed"),
            refreshedBookmarkData: nil,
            displayName: "removed",
            isDirectory: false,
            contentTypeIdentifier: nil
        )
        let blocking = BlockingShelfResolution(result: file)
        let state = ShelfStateViewModel(
            items: [item],
            resolver: ShelfBookmarkResolver(resolution: blocking.resolve)
        )

        let resolution = Task { await state.resolveFile(for: item) }
        let didStart = await blocking.waitUntilStarted()
        XCTAssertTrue(didStart)
        state.remove(item)
        blocking.unblock()

        let result = await resolution.value
        XCTAssertNil(result)
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertNil(state.resolvedFile(for: item))
    }

    @MainActor
    func testStaleRefreshPreservesPersistentID() async {
        let oldData = Data("stale".utf8)
        let refreshedData = Data("fresh".utf8)
        let id = UUID()
        let item = ShelfItem(id: id, kind: .file(bookmark: oldData), isTemporary: true)
        let resolver = ShelfBookmarkResolver { _, _ in
            ResolvedShelfFile(
                url: URL(fileURLWithPath: "/tmp/fresh"),
                refreshedBookmarkData: refreshedData,
                displayName: "fresh",
                isDirectory: false,
                contentTypeIdentifier: nil
            )
        }
        let state = ShelfStateViewModel(items: [item], resolver: resolver)

        _ = await state.resolveFile(for: item)

        XCTAssertEqual(state.items.first?.id, id)
        XCTAssertEqual(state.items.first?.isTemporary, true)
        guard case .file(let storedData) = state.items.first?.kind else {
            return XCTFail("Expected refreshed file item")
        }
        XCTAssertEqual(storedData, refreshedData)
    }

    @MainActor
    func testFailedExplicitRefreshClearsPreviouslyCachedResolution() async {
        let data = Data("refresh-failure".utf8)
        let item = ShelfItem(kind: .file(bookmark: data))
        let cachedFile = ResolvedShelfFile(
            url: URL(fileURLWithPath: "/tmp/previously-available"),
            refreshedBookmarkData: nil,
            displayName: "previously-available",
            isDirectory: false,
            contentTypeIdentifier: nil
        )
        let sequence = SequencedShelfResolution([cachedFile, nil])
        let state = ShelfStateViewModel(
            items: [item],
            resolver: ShelfBookmarkResolver(resolution: sequence.resolve)
        )

        let initialResult = await state.resolveFile(for: item)
        let refreshResult = await state.resolveFile(for: item, intent: .userInitiated, refresh: true)
        XCTAssertEqual(initialResult, cachedFile)
        XCTAssertNil(refreshResult)
        XCTAssertNil(state.resolvedFile(for: item))
        XCTAssertNil(state.resolvedFileURL(for: item))
        XCTAssertTrue(state.isFileUnavailable(item))
        XCTAssertEqual(sequence.intents, [.presentation, .userInitiated])
        XCTAssertEqual(state.items.first?.id, item.id)
        XCTAssertEqual(state.items.first?.kind, item.kind)
    }

    @MainActor
    func testExplicitRetryRecoversUnavailableFile() async {
        let item = ShelfItem(kind: .file(bookmark: Data("retry".utf8)))
        let recoveredFile = ResolvedShelfFile(
            url: URL(fileURLWithPath: "/tmp/recovered"),
            refreshedBookmarkData: nil,
            displayName: "recovered",
            isDirectory: false,
            contentTypeIdentifier: nil
        )
        let sequence = SequencedShelfResolution([nil, recoveredFile])
        let state = ShelfStateViewModel(
            items: [item],
            resolver: ShelfBookmarkResolver(resolution: sequence.resolve)
        )

        let initialResult = await state.resolveFile(for: item)
        XCTAssertNil(initialResult)
        XCTAssertTrue(state.isFileUnavailable(item))
        let retryResult = await state.resolveFile(for: item, intent: .userInitiated, refresh: true)
        XCTAssertEqual(retryResult, recoveredFile)
        XCTAssertEqual(state.resolvedFile(for: item), recoveredFile)
        XCTAssertFalse(state.isFileUnavailable(item))
    }

    @MainActor
    func testMixedDragTracksOnlyItemsThatProducedExports() {
        let available = ShelfItem(kind: .file(bookmark: Data("available".utf8)))
        let unavailable = ShelfItem(kind: .file(bookmark: Data("unavailable".utf8)))
        let text = ShelfItem(kind: .text(string: "text"))

        let exports = compactShelfExports([available, unavailable, text]) { item -> String? in
            item.id == unavailable.id ? nil : item.id.uuidString
        }

        XCTAssertEqual(exports.map(\.item.id), [available.id, text.id])
        XCTAssertEqual(exports.map(\.payload), [available.id.uuidString, text.id.uuidString])
    }

    @MainActor
    func testCleanupKeepsUnavailableItemsAndConcurrentAdds() async {
        let blocked = ShelfItem(kind: .file(bookmark: Data("disconnected".utf8)))
        let added = ShelfItem(kind: .text(string: "added while resolving"))
        let blocking = BlockingShelfResolution()
        let state = ShelfStateViewModel(
            items: [blocked],
            resolver: ShelfBookmarkResolver(resolution: blocking.resolve)
        )

        state.cleanupInvalidItems()
        let didStart = await blocking.waitUntilStarted()
        XCTAssertTrue(didStart)
        state.add([added])
        blocking.unblock()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(Set(state.items.map { $0.id }), Set([blocked.id, added.id]))
    }

    @MainActor
    func testFailedResolutionKeepsPersistedBookmarkAndFileFixture() async throws {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShelfFileResolutionTests-\(UUID().uuidString)")
        try Data("original".utf8).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }

        for payload in [Data(), Data("corrupt".utf8), Data("missing".utf8), Data("disconnected".utf8)] {
            let id = UUID()
            let item = ShelfItem(id: id, kind: .file(bookmark: payload))
            let state = ShelfStateViewModel(
                items: [item],
                resolver: ShelfBookmarkResolver { _, _ in nil }
            )
            let result = await state.resolveFile(for: item)
            XCTAssertNil(result)
            XCTAssertEqual(state.items.first?.id, id)
            guard case .file(let storedData) = state.items.first?.kind else {
                return XCTFail("Expected file item")
            }
            XCTAssertEqual(storedData, payload)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))
    }
}
