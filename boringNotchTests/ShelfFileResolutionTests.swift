import XCTest
import Combine
import SwiftUI
import AppKit
import UniformTypeIdentifiers
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
    func testNativeDragRefreshesBookmarkAfterExternalRename() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = root.appendingPathComponent("before.txt")
        let after = root.appendingPathComponent("after.txt")
        try Data("original".utf8).write(to: before)
        let bookmark = try before.bookmarkData(options: [])
        let item = ShelfItem(kind: .file(bookmark: bookmark))
        let state = ShelfStateViewModel(items: [item], resolver: ShelfBookmarkResolver { data, _ in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                                     bookmarkDataIsStale: &stale) else { return nil }
            return ResolvedShelfFile(url: url, refreshedBookmarkData: nil,
                                     displayName: url.lastPathComponent, isDirectory: false,
                                     contentTypeIdentifier: UTType.plainText.identifier)
        })
        _ = await state.resolveFile(for: item)
        try FileManager.default.moveItem(at: before, to: after)
        XCTAssertFalse(FileManager.default.fileExists(atPath: before.path))
        XCTAssertEqual(state.resolvedFileURL(for: item)?.lastPathComponent, "before.txt")

        let exports = await ShelfItemInteractionView<EmptyView>.InteractionView.prepareDragExports(
            for: [item], shelfState: state)
        let writer = try XCTUnwrap(exports.first?.payload as? NSURL)
        XCTAssertEqual((writer as URL).resolvingSymlinksInPath(), after.resolvingSymlinksInPath())
        XCTAssertTrue(writer.writableTypes(for: .general).contains(.fileURL))
        XCTAssertEqual(state.items.first?.id, item.id)
    }

    @MainActor
    func testNativeDragSkipsUnavailableFilesAndPreservesTextPayload() async {
        let available = ShelfItem(kind: .file(bookmark: Data("available".utf8)))
        let unavailable = ShelfItem(kind: .file(bookmark: Data()))
        let text = ShelfItem(kind: .text(string: "text"))
        let state = ShelfStateViewModel(items: [available, unavailable, text], resolver: ShelfBookmarkResolver { data, _ in
            guard !data.isEmpty else { return nil }
            return ResolvedShelfFile(url: URL(fileURLWithPath: "/tmp/available"), refreshedBookmarkData: nil,
                                     displayName: "available", isDirectory: false, contentTypeIdentifier: nil)
        })
        let exports = await ShelfItemInteractionView<EmptyView>.InteractionView.prepareDragExports(
            for: [available, unavailable, text], shelfState: state)
        XCTAssertEqual(exports.map(\.item.id), [available.id, text.id])
        XCTAssertTrue(exports.first?.payload is NSURL)
        XCTAssertTrue(exports.last?.payload is NSPasteboardItem)
    }

    @MainActor
    func testMouseUpAndRemovalCancelLateNativeDragPreparation() async throws {
        for removeItem in [false, true] {
            let item = ShelfItem(kind: .file(bookmark: Data("blocked-drag".utf8)))
            let blocking = BlockingShelfResolution(result: ResolvedShelfFile(
                url: URL(fileURLWithPath: "/tmp/late-drag"), refreshedBookmarkData: nil,
                displayName: "late-drag", isDirectory: false, contentTypeIdentifier: nil))
            let state = ShelfStateViewModel(items: [item], resolver: ShelfBookmarkResolver(resolution: blocking.resolve))
            let view = ShelfItemInteractionView<EmptyView>.InteractionView()
            view.item = item
            view.shelfState = state
            let didBegin = expectation(description: "late drag never begins")
            didBegin.isInverted = true
            view.beginPreparedDrag = { _, _ in didBegin.fulfill() }
            func event(_ type: NSEvent.EventType, _ x: CGFloat) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 0),
                                                modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
            }
            view.mouseDown(with: try event(.leftMouseDown, 0))
            view.mouseDragged(with: try event(.leftMouseDragged, 10))
            let started = await blocking.waitUntilStarted()
            XCTAssertTrue(started)
            if removeItem { state.remove(item) }
            else { view.mouseUp(with: try event(.leftMouseUp, 10)) }
            blocking.unblock()
            await fulfillment(of: [didBegin], timeout: 0.2)
            view.cancelDragPreparation()
        }
    }

    @MainActor
    func testOpenWithMenuLoadsDirectApplicationsAndCancelsOnClose() async throws {
        let link = ShelfItem(kind: .link(url: try XCTUnwrap(URL(string: "https://example.com"))))
        let application = ShelfContextMenuBuilder.OpenWithApplication(
            url: URL(fileURLWithPath: "/Applications/Example.app"), title: "Example",
            isDefault: true, iconData: nil)
        for closesMenu in [false, true] {
            var discovery: CheckedContinuation<[ShelfContextMenuBuilder.OpenWithApplication], Never>?
            let started = expectation(description: "application discovery starts")
            let view = NSView()
            let menu = ShelfContextMenuBuilder.makeMenu(
                item: link, in: view, selectedItems: [link], onShare: { _ in }, onQuickLook: { _ in },
                discoverApplications: { _ in
                    await withCheckedContinuation { continuation in
                        discovery = continuation
                        started.fulfill()
                    }
                })
            let submenu = try XCTUnwrap(menu.items.first(where: { $0.title == Strings.openWith })?.submenu)
            XCTAssertEqual(submenu.items.first?.title, String(localized: "Loading…"))
            XCTAssertEqual(submenu.items.last?.representedObject as? String, "__OTHER__")
            await fulfillment(of: [started], timeout: 1)
            if closesMenu { menu.delegate?.menuDidClose?(menu) }
            discovery?.resume(returning: [application])
            // Yield to the menu's continuation without opening any native menu or application.
            try await Task.sleep(for: .milliseconds(30))
            if closesMenu {
                XCTAssertEqual(submenu.items.first?.title, String(localized: "Loading…"))
            } else {
                XCTAssertEqual(submenu.items.first?.representedObject as? URL, application.url)
                XCTAssertEqual(submenu.items.first?.state, .on)
                XCTAssertNotNil(submenu.items.first?.target)
                XCTAssertNotNil(submenu.items.first?.action)
                menu.delegate?.menuDidClose?(menu)
            }
        }
    }

    @MainActor
    func testSameIDBookmarkReplacementRefreshesRetainedItemModelAndDragURL() async throws {
        let oldData = Data("old-bookmark".utf8)
        let newData = Data("renamed-bookmark".utf8)
        let id = UUID()
        let oldItem = ShelfItem(id: id, kind: .file(bookmark: oldData))
        let oldFile = ResolvedShelfFile(
            url: URL(fileURLWithPath: "/tmp/old-name"),
            refreshedBookmarkData: nil,
            displayName: "old-name",
            isDirectory: false,
            contentTypeIdentifier: UTType.data.identifier
        )
        let renamedFile = ResolvedShelfFile(
            url: URL(fileURLWithPath: "/tmp/new-name"),
            refreshedBookmarkData: nil,
            displayName: "new-name",
            isDirectory: false,
            contentTypeIdentifier: UTType.data.identifier
        )
        let state = ShelfStateViewModel(
            items: [oldItem],
            resolver: ShelfBookmarkResolver { data, _ in
                data == oldData ? oldFile : renamedFile
            }
        )
        let viewModel = ShelfItemViewModel(
            item: oldItem,
            shelfState: state,
            loadsThumbnails: false
        )

        await viewModel.synchronize(with: oldItem)
        XCTAssertEqual(viewModel.displayName, "old-name")
        XCTAssertEqual(viewModel.resolvedFileURL, oldFile.url)

        state.updateBookmark(for: oldItem, bookmark: newData)
        let renamedItem = try XCTUnwrap(state.items.first)
        XCTAssertEqual(renamedItem.id, id)
        XCTAssertNil(viewModel.resolvedFileURL)

        await viewModel.synchronize(with: renamedItem)
        XCTAssertEqual(viewModel.displayName, "new-name")
        XCTAssertEqual(viewModel.resolvedFileURL, renamedFile.url)
        let exports = await ShelfItemInteractionView<EmptyView>.InteractionView.prepareDragExports(
            for: [renamedItem], shelfState: state)
        XCTAssertEqual(exports.first?.payload as? NSURL, renamedFile.url as NSURL)
    }

    @MainActor
    func testQuickLookSelectionRetriesUnavailableFileAndRecovers() async throws {
        let item = ShelfItem(kind: .file(bookmark: Data("quick-look-retry".utf8)))
        let recoveredURL = try XCTUnwrap(URL(string: "https://example.com/recovered"))
        let recoveredFile = ResolvedShelfFile(
            url: recoveredURL,
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
        let service = QuickLookService(
            shelfState: state,
            observeShelfSelection: false,
            presentsPanel: false
        )

        service.isQuickLookOpen = true
        await service.applyShelfSelection(selectedIDs: [item.id])
        XCTAssertFalse(service.isQuickLookOpen)
        XCTAssertTrue(service.urls.isEmpty)

        service.isQuickLookOpen = true
        await service.applyShelfSelection(selectedIDs: [item.id])
        try? await Task.sleep(for: .milliseconds(75))
        XCTAssertTrue(service.isQuickLookOpen)
        XCTAssertEqual(service.urls, [recoveredURL])
        XCTAssertEqual(service.selectedURL, recoveredURL)
    }

    @MainActor
    func testLateQuickLookResolutionCannotReplaceNewerSelection() async throws {
        let blockedItem = ShelfItem(kind: .file(bookmark: Data("blocked-preview".utf8)))
        let linkURL = try XCTUnwrap(URL(string: "https://example.com/newer"))
        let linkItem = ShelfItem(kind: .link(url: linkURL))
        let blockedFile = ResolvedShelfFile(
            url: try XCTUnwrap(URL(string: "https://example.com/late")),
            refreshedBookmarkData: nil,
            displayName: "late",
            isDirectory: false,
            contentTypeIdentifier: nil
        )
        let blocking = BlockingShelfResolution(result: blockedFile)
        let state = ShelfStateViewModel(
            items: [blockedItem, linkItem],
            resolver: ShelfBookmarkResolver(resolution: blocking.resolve)
        )
        let service = QuickLookService(
            shelfState: state,
            observeShelfSelection: false,
            presentsPanel: false
        )
        service.isQuickLookOpen = true

        let lateUpdate = Task {
            await service.applyShelfSelection(selectedIDs: [blockedItem.id])
        }
        let didStart = await blocking.waitUntilStarted()
        XCTAssertTrue(didStart)
        await service.applyShelfSelection(selectedIDs: [linkItem.id])
        blocking.unblock()
        await lateUpdate.value
        try? await Task.sleep(for: .milliseconds(75))

        XCTAssertTrue(service.isQuickLookOpen)
        XCTAssertEqual(service.urls, [linkURL])
        XCTAssertEqual(service.selectedURL, linkURL)
    }

    @MainActor
    func testPendingQuickLookReplacementKeepsCurrentPreviewUntilSuccessfulSwap() async throws {
        let item = ShelfItem(kind: .file(bookmark: Data("replacement-preview".utf8)))
        let currentURL = try XCTUnwrap(URL(string: "https://example.com/current"))
        let replacementURL = try XCTUnwrap(URL(string: "https://example.com/replacement"))
        let replacementFile = ResolvedShelfFile(
            url: replacementURL,
            refreshedBookmarkData: nil,
            displayName: "replacement",
            isDirectory: false,
            contentTypeIdentifier: nil
        )
        let blocking = BlockingShelfResolution(result: replacementFile)
        let state = ShelfStateViewModel(
            items: [item],
            resolver: ShelfBookmarkResolver(resolution: blocking.resolve)
        )
        let service = QuickLookService(
            shelfState: state,
            observeShelfSelection: false,
            presentsPanel: false
        )
        service.show(urls: [currentURL])
        try? await Task.sleep(for: .milliseconds(75))
        var selectionUpdates: [URL?] = []
        let selectionObservation = service.$selectedURL
            .dropFirst()
            .sink { selectionUpdates.append($0) }
        defer { selectionObservation.cancel() }

        let replacement = Task {
            await service.applyShelfSelection(selectedIDs: [item.id])
        }
        let didStart = await blocking.waitUntilStarted()
        XCTAssertTrue(didStart)
        XCTAssertTrue(service.isQuickLookOpen)
        XCTAssertEqual(service.urls, [currentURL])
        XCTAssertEqual(service.selectedURL, currentURL)

        blocking.unblock()
        await replacement.value
        try? await Task.sleep(for: .milliseconds(75))
        XCTAssertTrue(service.isQuickLookOpen)
        XCTAssertEqual(service.urls, [replacementURL])
        XCTAssertEqual(service.selectedURL, replacementURL)
        XCTAssertEqual(selectionUpdates, [replacementURL])
    }

    @MainActor
    func testUnavailableQuickLookReplacementHidesOnlyAfterResolutionCompletes() async throws {
        let item = ShelfItem(kind: .file(bookmark: Data("unavailable-preview".utf8)))
        let currentURL = try XCTUnwrap(URL(string: "https://example.com/current"))
        let blocking = BlockingShelfResolution()
        let state = ShelfStateViewModel(
            items: [item],
            resolver: ShelfBookmarkResolver(resolution: blocking.resolve)
        )
        let service = QuickLookService(
            shelfState: state,
            observeShelfSelection: false,
            presentsPanel: false
        )
        service.show(urls: [currentURL])
        try? await Task.sleep(for: .milliseconds(75))

        let replacement = Task {
            await service.applyShelfSelection(selectedIDs: [item.id])
        }
        let didStart = await blocking.waitUntilStarted()
        XCTAssertTrue(didStart)
        XCTAssertTrue(service.isQuickLookOpen)
        XCTAssertEqual(service.selectedURL, currentURL)

        blocking.unblock()
        await replacement.value
        XCTAssertFalse(service.isQuickLookOpen)
        XCTAssertTrue(service.urls.isEmpty)
        XCTAssertNil(service.selectedURL)
    }

    @MainActor
    func testNativeQuickLookCloseInvalidatesPendingReplacement() async throws {
        let item = ShelfItem(kind: .file(bookmark: Data("native-close-preview".utf8)))
        let currentURL = try XCTUnwrap(URL(string: "https://example.com/current"))
        let lateFile = ResolvedShelfFile(
            url: try XCTUnwrap(URL(string: "https://example.com/late")),
            refreshedBookmarkData: nil,
            displayName: "late",
            isDirectory: false,
            contentTypeIdentifier: nil
        )
        let blocking = BlockingShelfResolution(result: lateFile)
        let state = ShelfStateViewModel(
            items: [item],
            resolver: ShelfBookmarkResolver(resolution: blocking.resolve)
        )
        let service = QuickLookService(
            shelfState: state,
            observeShelfSelection: false,
            presentsPanel: false
        )
        service.show(urls: [currentURL])
        try? await Task.sleep(for: .milliseconds(75))

        let replacement = Task {
            await service.applyShelfSelection(selectedIDs: [item.id])
        }
        let didStart = await blocking.waitUntilStarted()
        XCTAssertTrue(didStart)
        service.handleNativePreviewClose()
        XCTAssertFalse(service.isQuickLookOpen)
        XCTAssertNil(service.selectedURL)

        blocking.unblock()
        await replacement.value
        try? await Task.sleep(for: .milliseconds(75))
        XCTAssertFalse(service.isQuickLookOpen)
        XCTAssertTrue(service.urls.isEmpty)
        XCTAssertNil(service.selectedURL)
    }

    @MainActor
    func testHideInvalidatesPendingQuickLookResolution() async throws {
        let item = ShelfItem(kind: .file(bookmark: Data("dismissed-preview".utf8)))
        let lateFile = ResolvedShelfFile(
            url: try XCTUnwrap(URL(string: "https://example.com/late")),
            refreshedBookmarkData: nil,
            displayName: "late",
            isDirectory: false,
            contentTypeIdentifier: nil
        )
        let blocking = BlockingShelfResolution(result: lateFile)
        let state = ShelfStateViewModel(
            items: [item],
            resolver: ShelfBookmarkResolver(resolution: blocking.resolve)
        )
        let service = QuickLookService(
            shelfState: state,
            observeShelfSelection: false,
            presentsPanel: false
        )
        service.isQuickLookOpen = true

        let lateUpdate = Task {
            await service.applyShelfSelection(selectedIDs: [item.id])
        }
        let didStart = await blocking.waitUntilStarted()
        XCTAssertTrue(didStart)
        service.hide()
        blocking.unblock()
        await lateUpdate.value

        XCTAssertFalse(service.isQuickLookOpen)
        XCTAssertTrue(service.urls.isEmpty)
        XCTAssertNil(service.selectedURL)
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
