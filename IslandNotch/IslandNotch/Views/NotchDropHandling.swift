//  NotchDropHandling.swift
//  IslandNotch
//
//  Purpose: Shared drag-and-drop import for the expanded notch shelf.
//  Layer: View

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum NotchDropHandling {
    static let types: [UTType] = [
        .fileURL,
        .image,
        .png,
        .jpeg,
        .gif,
        .tiff,
        .heic,
        .webP,
        .data,
    ]

    /// Imports all dropped providers. Returns true only after at least one import succeeds.
    @MainActor
    static func handle(_ providers: [NSItemProvider], store: ScreenshotStore) async -> Bool {
        guard !providers.isEmpty else { return false }
        var anySuccess = false
        for provider in providers {
            if await importFromProvider(provider, store: store) {
                anySuccess = true
            }
        }
        Log.store.debug("drop import success=\(anySuccess) (\(providers.count) provider(s))")
        return anySuccess
    }

    @MainActor
    private static func importFromProvider(_ provider: NSItemProvider, store: ScreenshotStore) async -> Bool {
        if await importFileURL(from: provider, store: store) { return true }
        return await importImageData(from: provider, store: store)
    }

    @MainActor
    private static func importFileURL(from provider: NSItemProvider, store: ScreenshotStore) async -> Bool {
        let fileTypes: [UTType] = [.fileURL, .png, .jpeg, .gif, .tiff, .heic, .webP, .data]
        guard let type = fileTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                if let error {
                    Log.store.error("loadFileRepresentation failed (\(type.identifier)): \(error.localizedDescription)")
                    continuation.resume(returning: false)
                    return
                }
                guard let url else {
                    Log.store.error("loadFileRepresentation returned nil url (\(type.identifier))")
                    continuation.resume(returning: false)
                    return
                }
                Task { @MainActor in
                    let imported = await store.importImage(from: url) != nil
                    continuation.resume(returning: imported)
                }
            }
        }
    }

    @MainActor
    private static func importImageData(from provider: NSItemProvider, store: ScreenshotStore) async -> Bool {
        let imageTypes: [UTType] = [.image, .png, .jpeg, .gif, .tiff, .heic, .webP]
        guard let type = imageTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error {
                    Log.store.error("loadDataRepresentation failed (\(type.identifier)): \(error.localizedDescription)")
                    continuation.resume(returning: false)
                    return
                }
                guard let data, let image = NSImage(data: data) else {
                    Log.store.error("loadDataRepresentation: invalid image bytes (\(type.identifier))")
                    continuation.resume(returning: false)
                    return
                }
                Task { @MainActor in
                    let imported = await store.importImage(image) != nil
                    continuation.resume(returning: imported)
                }
            }
        }
    }
}
