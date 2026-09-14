//
//  ShelfTransferDecoder.swift
//  boringNotch
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct ShelfTransferFile: Equatable, Sendable {
    let url: URL
    let isOwnedTemporary: Bool
}

enum ShelfTransferValue: Equatable, Sendable {
    case file(ShelfTransferFile)
    case link(URL)
    case text(String)
}

/// Owns resources for one decoded transfer until a consumer explicitly releases them.
final class ShelfTransferResources: @unchecked Sendable {
    private let lock = NSLock()
    private let storage: TemporaryFileStorageService
    private var securityScopedURLs: [URL] = []
    private var ownedTemporaryURLs: [URL] = []
    private var isReleased = false

    init(storage: TemporaryFileStorageService = .shared) {
        self.storage = storage
    }

    @discardableResult
    func beginAccessingSecurityScope(for url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        lock.lock()
        let isAlreadyRegistered = securityScopedURLs.contains {
            $0.standardizedFileURL == standardizedURL
        }
        let canRegister = !isReleased
        lock.unlock()
        guard canRegister, !isAlreadyRegistered else { return isAlreadyRegistered }

        let didStart = url.startAccessingSecurityScopedResource()
        if didStart {
            registerSecurityScope(for: url)
        }
        return didStart
    }

    func registerSecurityScope(for url: URL) {
        lock.lock()
        if isReleased {
            lock.unlock()
            url.stopAccessingSecurityScopedResource()
            return
        }
        securityScopedURLs.append(url)
        lock.unlock()
    }

    func registerOwnedTemporaryFile(_ url: URL) {
        lock.lock()
        if isReleased {
            lock.unlock()
            storage.removeTemporaryFileIfNeeded(at: url)
            return
        }
        ownedTemporaryURLs.append(url)
        lock.unlock()
    }

    /// Transfers deletion responsibility to the shelf's persisted temporary item.
    func relinquishOwnedTemporaryFile(_ url: URL) {
        lock.lock()
        ownedTemporaryURLs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        lock.unlock()
    }

    func release() {
        lock.lock()
        guard !isReleased else {
            lock.unlock()
            return
        }
        isReleased = true
        let scopedURLs = securityScopedURLs
        let temporaryURLs = ownedTemporaryURLs
        securityScopedURLs.removeAll()
        ownedTemporaryURLs.removeAll()
        lock.unlock()

        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        for url in temporaryURLs {
            storage.removeTemporaryFileIfNeeded(at: url)
        }
    }
}

struct ShelfTransferBatch: Sendable {
    let values: [ShelfTransferValue]
    let resources: ShelfTransferResources
}

struct ShelfTransferDecoder: @unchecked Sendable {
    private let storage: TemporaryFileStorageService

    init(storage: TemporaryFileStorageService = .shared) {
        self.storage = storage
    }

    func decode(_ providers: [NSItemProvider]) async -> ShelfTransferBatch {
        let resources = ShelfTransferResources(storage: storage)
        var values: [ShelfTransferValue] = []
        values.reserveCapacity(providers.count)

        // Preserve provider order and keep each provider independent when another one fails.
        for provider in providers {
            if let value = await decode(provider, resources: resources) {
                values.append(value)
            }
        }
        return ShelfTransferBatch(values: values, resources: resources)
    }

    private func decode(
        _ provider: NSItemProvider,
        resources: ShelfTransferResources
    ) async -> ShelfTransferValue? {
        if let url = await provider.extractFileURL(),
           let file = usableFile(at: url, isOwnedTemporary: false, resources: resources) {
            return .file(file)
        }

        let promiseTypes = promisedTypeIdentifiers(for: provider)
        if let file = await firstPromisedFile(
            from: provider,
            typeIdentifiers: promiseTypes.specific,
            resources: resources
        ) {
            return .file(file)
        }

        if let url = await provider.extractURL() {
            if url.isFileURL {
                if let file = usableFile(at: url, isOwnedTemporary: false, resources: resources) {
                    return .file(file)
                }
            } else {
                return .link(url)
            }
        }

        if let file = await firstPromisedFile(
            from: provider,
            typeIdentifiers: promiseTypes.generic,
            resources: resources
        ) {
            return .file(file)
        }

        if let text = await provider.extractText() {
            return .text(text)
        }

        if let data = await provider.loadData(),
           let url = await storage.createTempFile(
               for: .data(data, suggestedName: provider.suggestedName)
           ) {
            resources.registerOwnedTemporaryFile(url)
            return .file(ShelfTransferFile(url: url, isOwnedTemporary: true))
        }

        return nil
    }

    private func firstPromisedFile(
        from provider: NSItemProvider,
        typeIdentifiers: [String],
        resources: ShelfTransferResources
    ) async -> ShelfTransferFile? {
        for typeIdentifier in typeIdentifiers {
            if let url = await provider.loadOwnedFileRepresentation(
                forTypeIdentifier: typeIdentifier,
                storage: storage
            ) {
                resources.registerOwnedTemporaryFile(url)
                return ShelfTransferFile(url: url, isOwnedTemporary: true)
            }
        }
        return nil
    }

    private func usableFile(
        at url: URL,
        isOwnedTemporary: Bool,
        resources: ShelfTransferResources
    ) -> ShelfTransferFile? {
        guard url.isFileURL else { return nil }
        let didStartAccess = url.startAccessingSecurityScopedResource()
        let isUsable = FileManager.default.fileExists(atPath: url.path)
            && FileManager.default.isReadableFile(atPath: url.path)
        guard isUsable else {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
            return nil
        }
        if didStartAccess {
            resources.registerSecurityScope(for: url)
        }
        return ShelfTransferFile(url: url, isOwnedTemporary: isOwnedTemporary)
    }

    private func promisedTypeIdentifiers(
        for provider: NSItemProvider
    ) -> (specific: [String], generic: [String]) {
        var specific: [String] = []
        var generic: [String] = []
        let genericTypes: Set<String> = [
            UTType.data.identifier,
            UTType.item.identifier,
            UTType.content.identifier
        ]

        for identifier in provider.registeredTypeIdentifiers {
            guard let type = UTType(identifier),
                  !type.conforms(to: .fileURL),
                  !type.conforms(to: .url),
                  !type.conforms(to: .plainText),
                  type.conforms(to: .data)
                    || type.conforms(to: .content)
                    || type.conforms(to: .item)
                    || type.conforms(to: .directory)
                    || type.conforms(to: .package) else {
                continue
            }
            if genericTypes.contains(identifier) {
                generic.append(identifier)
            } else {
                specific.append(identifier)
            }
        }
        return (specific, generic)
    }
}
