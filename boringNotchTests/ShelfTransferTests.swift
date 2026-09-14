import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import boringNotch

private enum ShelfTransferTestError: Error {
    case promisedFileFailed
}

final class ShelfTransferTests: XCTestCase {
    func testPromiseBeatsInaccessibleFileURLAndFallbackTextWithoutDeletingSource() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.sources.appendingPathComponent("message.pdf")
        try Data("attachment".utf8).write(to: source)
        let missingURL = fixture.sources.appendingPathComponent("missing.pdf")
        let provider = promisedProvider(
            source: source,
            type: .pdf,
            suggestedName: "../../safe-message.pdf",
            fallbackText: "fallback",
            fileURL: missingURL
        )

        let batch = await ShelfTransferDecoder(storage: fixture.storage).decode([provider])
        defer { batch.resources.release() }
        guard case .file(let file) = batch.values.first else {
            return XCTFail("Expected the promised file")
        }

        XCTAssertTrue(file.isOwnedTemporary)
        XCTAssertEqual(file.url.lastPathComponent, "safe-message.pdf")
        XCTAssertNotEqual(file.url.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: file.url), Data("attachment".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testMixedProvidersRemainIndependentAndDuplicateNamesHaveUniqueURLs() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let firstSource = fixture.sources.appendingPathComponent("first.pdf")
        let secondSource = fixture.sources.appendingPathComponent("second.pdf")
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)
        let first = promisedProvider(source: firstSource, type: .pdf, suggestedName: "same.pdf")
        let text = NSItemProvider(object: "middle" as NSString)
        let second = promisedProvider(source: secondSource, type: .pdf, suggestedName: "same.pdf")

        let batch = await ShelfTransferDecoder(storage: fixture.storage).decode([first, text, second])
        defer { batch.resources.release() }

        XCTAssertEqual(batch.values.count, 3)
        guard case .file(let firstFile) = batch.values[0],
              case .text(let decodedText) = batch.values[1],
              case .file(let secondFile) = batch.values[2] else {
            return XCTFail("Expected file, text, file in provider order")
        }
        XCTAssertEqual(decodedText, "middle")
        XCTAssertEqual(firstFile.url.lastPathComponent, "same.pdf")
        XCTAssertEqual(secondFile.url.lastPathComponent, "same.pdf")
        XCTAssertNotEqual(firstFile.url, secondFile.url)
        XCTAssertEqual(try Data(contentsOf: firstFile.url), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: secondFile.url), Data("second".utf8))
    }

    func testFailedPromiseFallsBackToText() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.pdf.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(nil, false, ShelfTransferTestError.promisedFileFailed)
            return nil
        }
        provider.registerObject("fallback text" as NSString, visibility: .all)

        let batch = await ShelfTransferDecoder(storage: fixture.storage).decode([provider])
        defer { batch.resources.release() }
        XCTAssertEqual(batch.values, [.text("fallback text")])
    }

    func testPromisedPackageCopiesDirectoryContents() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sibling = fixture.sources.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sibling)
        let package = fixture.sources.appendingPathComponent("Document.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: package.appendingPathComponent("contents.txt"))
        let provider = promisedProvider(
            source: package,
            type: .package,
            suggestedName: "Document.bundle"
        )

        XCTAssertTrue(ShelfTransferTypes.supports([provider]))
        let batch = await ShelfTransferDecoder(storage: fixture.storage).decode([provider])
        defer { batch.resources.release() }
        guard case .file(let file) = batch.values.first else {
            return XCTFail("Expected copied package")
        }
        XCTAssertEqual(
            try Data(contentsOf: file.url.appendingPathComponent("contents.txt")),
            Data("inside".utf8)
        )
        batch.resources.release()

        XCTAssertTrue(FileManager.default.fileExists(atPath: package.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sources.path))
        XCTAssertEqual(try Data(contentsOf: sibling), Data("keep".utf8))
    }

    func testPromisedDirectoryCopiesHierarchyWithoutDeletingProviderParent() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sibling = fixture.sources.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sibling)
        let directory = fixture.sources.appendingPathComponent("Folder", isDirectory: true)
        let nested = directory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: nested.appendingPathComponent("contents.txt"))
        let provider = promisedProvider(
            source: directory,
            type: .directory,
            suggestedName: "Folder"
        )

        XCTAssertTrue(ShelfTransferTypes.supports([provider]))
        let batch = await ShelfTransferDecoder(storage: fixture.storage).decode([provider])
        defer { batch.resources.release() }
        guard case .file(let file) = batch.values.first else {
            return XCTFail("Expected copied directory")
        }
        XCTAssertEqual(
            try Data(contentsOf: file.url.appendingPathComponent("Nested/contents.txt")),
            Data("inside".utf8)
        )
        batch.resources.release()

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sources.path))
        XCTAssertEqual(try Data(contentsOf: sibling), Data("keep".utf8))
    }

    @MainActor
    func testShelfImportClaimsOwnedPromiseUntilTemporaryItemRemoval() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.sources.appendingPathComponent("shelf.pdf")
        try Data("shelf".utf8).write(to: source)
        let provider = promisedProvider(source: source, type: .pdf, suggestedName: "shelf.pdf")

        let items = await ShelfDropService.items(
            from: [provider],
            decoder: ShelfTransferDecoder(storage: fixture.storage)
        )

        let item = try XCTUnwrap(items.first)
        XCTAssertTrue(item.isTemporary)
        guard case .file = item.kind else { return XCTFail("Expected shelf file") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try ownedEntries(in: fixture.owned).count, 1)
    }

    @MainActor
    func testQuickShareCancellationReleasesDecodedOwnedFile() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.sources.appendingPathComponent("share.pdf")
        try Data("share".utf8).write(to: source)
        let provider = promisedProvider(source: source, type: .pdf, suggestedName: "share.pdf")
        let service = QuickShareService(
            storage: fixture.storage,
            automaticallyDiscoversProviders: false
        )

        await service.shareDroppedFiles(
            [provider],
            using: .systemShareMenu,
            from: nil
        )

        XCTAssertEqual(service.lastShareError, "The System Share Menu could not be shown.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(try ownedEntries(in: fixture.owned).isEmpty)
    }

    @MainActor
    func testSharingResourcesSurviveDelayAndReleaseOnSuccessOrFailure() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let createdSuccessURL = await fixture.storage.createTempFile(
            for: .data(Data("success".utf8), suggestedName: "success.txt")
        )
        let successURL = try XCTUnwrap(createdSuccessURL)
        let resources = ShelfTransferResources(storage: fixture.storage)
        resources.registerOwnedTemporaryFile(successURL)
        let successDelegate = SharingLifecycleDelegate(
            id: UUID(),
            onEnd: resources.release,
            onBegin: {},
            onFinish: {}
        )
        successDelegate.markServiceBegan()

        try? await Task.sleep(for: .seconds(2.1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: successURL.path))
        let sharingService = NSSharingService(
            title: "Test",
            image: NSImage(),
            alternateImage: nil,
            handler: {}
        )
        successDelegate.sharingService(sharingService, didShareItems: [successURL])
        XCTAssertFalse(FileManager.default.fileExists(atPath: successURL.path))

        let createdFailureURL = await fixture.storage.createTempFile(
            for: .data(Data("failure".utf8), suggestedName: "failure.txt")
        )
        let failureURL = try XCTUnwrap(createdFailureURL)
        let failureResources = ShelfTransferResources(storage: fixture.storage)
        failureResources.registerOwnedTemporaryFile(failureURL)
        let failureDelegate = SharingLifecycleDelegate(
            id: UUID(),
            onEnd: failureResources.release,
            onBegin: {},
            onFinish: {}
        )
        failureDelegate.markServiceBegan()
        failureDelegate.sharingService(
            sharingService,
            didFailToShareItems: [failureURL],
            error: ShelfTransferTestError.promisedFileFailed
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: failureURL.path))
    }

    @MainActor
    func testCancellingUnstartedDelegateDoesNotEndAnotherActiveShare() {
        let manager = SharingStateManager.shared
        XCTAssertFalse(manager.preventNotchClose)

        let activeDelegate = manager.makeDelegate()
        defer { activeDelegate.cancel() }
        activeDelegate.markServiceBegan()
        XCTAssertTrue(manager.preventNotchClose)

        let unstartedDelegate = manager.makeDelegate()
        unstartedDelegate.cancel()

        XCTAssertTrue(manager.preventNotchClose)

        let service = makeSharingService()
        activeDelegate.sharingService(service, didShareItems: ["shared"])
        XCTAssertFalse(manager.preventNotchClose)
    }

    @MainActor
    func testPickerServiceLifecycleBalancesOnceAndIgnoresLateCallbacks() {
        var beginCount = 0
        var finishCount = 0
        var endCount = 0
        let delegate = SharingLifecycleDelegate(
            id: UUID(),
            onEnd: { endCount += 1 },
            onBegin: { beginCount += 1 },
            onFinish: { finishCount += 1 }
        )
        let service = makeSharingService()
        let picker = NSSharingServicePicker(items: ["shared"])

        delegate.markPickerBegan()
        delegate.sharingServicePicker(picker, didChoose: service)
        delegate.sharingService(service, willShareItems: ["shared"])
        delegate.sharingService(service, didShareItems: ["shared"])
        delegate.sharingService(service, didShareItems: ["duplicate"])
        delegate.sharingService(
            service,
            didFailToShareItems: ["late failure"],
            error: ShelfTransferTestError.promisedFileFailed
        )
        delegate.cancel()
        delegate.markPickerBegan()
        delegate.markServiceBegan()
        delegate.sharingService(service, willShareItems: ["late begin"])

        XCTAssertEqual(beginCount, 1)
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(endCount, 1)

        var cancelledBeginCount = 0
        var cancelledFinishCount = 0
        var cancelledEndCount = 0
        let cancelledDelegate = SharingLifecycleDelegate(
            id: UUID(),
            onEnd: { cancelledEndCount += 1 },
            onBegin: { cancelledBeginCount += 1 },
            onFinish: { cancelledFinishCount += 1 }
        )
        cancelledDelegate.cancel()
        cancelledDelegate.sharingService(service, willShareItems: ["late begin"])
        cancelledDelegate.sharingService(service, didShareItems: ["late completion"])

        XCTAssertEqual(cancelledBeginCount, 0)
        XCTAssertEqual(cancelledFinishCount, 0)
        XCTAssertEqual(cancelledEndCount, 1)
    }

    @MainActor
    func testDynamicThirdPartySharingDiscoveryUsesActualItems() async throws {
        var receivedItems: [[Any]] = []
        let extensionService = NSSharingService(title: "Third Party Destination", image: NSImage(),
                                               alternateImage: nil, handler: {})
        let finder = ShareServiceFinder { items in
            receivedItems.append(items)
            return [extensionService]
        }
        let fileURL = URL(fileURLWithPath: "/tmp/actual-share-file")
        let services = await finder.findApplicableServices(for: [fileURL])
        XCTAssertTrue(services.contains { $0.name.rawValue == extensionService.title && $0.service === extensionService })
        XCTAssertEqual(receivedItems.count, 1)
        XCTAssertEqual(receivedItems.first?.first as? URL, fileURL)
    }

    func testStableSharingIdentityIgnoresLocalizedTitleAndPreservesUnknownChoice() {
        let localizedAirDrop = QuickShareProvider(
            id: NSSharingService.Name.sendViaAirDrop.rawValue,
            displayName: "Envoyer par AirDrop",
            supportsRawText: false,
            isAvailable: true
        )

        XCTAssertEqual(
            QuickShareProvider.migratedSelection(
                "Envoyer par AirDrop",
                availableProviders: [localizedAirDrop, .systemShareMenu]
            ),
            NSSharingService.Name.sendViaAirDrop.rawValue
        )
        XCTAssertEqual(
            QuickShareProvider.migratedSelection(
                "unavailable.third-party.destination",
                availableProviders: [localizedAirDrop, .systemShareMenu]
            ),
            "unavailable.third-party.destination"
        )
    }

    func testTransferTypeAcceptanceIsExistential() {
        XCTAssertTrue(
            ShelfTransferTypes.supports(
                typeIdentifiers: ["com.example.private", UTType.pdf.identifier]
            )
        )
        XCTAssertFalse(
            ShelfTransferTypes.supports(typeIdentifiers: ["com.example.private"])
        )
        XCTAssertTrue(
            ShelfTransferTypes.supports(typeIdentifiers: [UTType.directory.identifier])
        )
        XCTAssertTrue(
            ShelfTransferTypes.supports(typeIdentifiers: [UTType.package.identifier])
        )
    }

    private func makeFixture() throws -> (
        root: URL,
        sources: URL,
        owned: URL,
        storage: TemporaryFileStorageService
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShelfTransferTests-\(UUID().uuidString)", isDirectory: true)
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let owned = root.appendingPathComponent("Owned", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        return (root, sources, owned, TemporaryFileStorageService(baseDirectory: owned))
    }

    private func promisedProvider(
        source: URL,
        type: UTType,
        suggestedName: String,
        fallbackText: String? = nil,
        fileURL: URL? = nil
    ) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = suggestedName
        if let fileURL {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier,
                visibility: .all
            ) { completion in
                completion(Data(fileURL.absoluteString.utf8), nil)
                return nil
            }
        }
        provider.registerFileRepresentation(
            forTypeIdentifier: type.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(source, false, nil)
            return nil
        }
        if let fallbackText {
            provider.registerObject(fallbackText as NSString, visibility: .all)
        }
        return provider
    }

    private func makeSharingService() -> NSSharingService {
        NSSharingService(
            title: "Test",
            image: NSImage(),
            alternateImage: nil,
            handler: {}
        )
    }

    private func ownedEntries(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
    }
}
