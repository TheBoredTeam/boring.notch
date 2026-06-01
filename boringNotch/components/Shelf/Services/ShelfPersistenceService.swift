//
//  ShelfPersistenceService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import Foundation

// Access model types
@_exported import struct Foundation.URL


final class ShelfPersistenceService {
    static let shared = ShelfPersistenceService()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = (support ?? fm.temporaryDirectory).appendingPathComponent("boringNotch", isDirectory: true).appendingPathComponent("Shelf", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("items.json")
        encoder.outputFormatting = [.prettyPrinted]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601

        // Sandbox-flip migration: when the app previously ran sandboxed, the shelf
        // store lived inside the app container. After dropping the sandbox the same
        // relative path resolves to the real ~/Library/Application Support, so copy
        // the old container store across on first unsandboxed launch to avoid the
        // shelf appearing "wiped." One-shot: only when the new path doesn't exist yet.
        Self.migrateFromSandboxContainerIfNeeded(to: fileURL, using: fm)
    }

    /// Copies a pre-flip sandboxed `items.json` from the app container into the
    /// real Application Support location, but only if no store exists there yet.
    private static func migrateFromSandboxContainerIfNeeded(to destination: URL, using fm: FileManager) {
        guard !fm.fileExists(atPath: destination.path) else { return }

        let containerStore = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent("theboringteam.boringnotch", isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support/boringNotch/Shelf", isDirectory: true)
            .appendingPathComponent("items.json")

        guard fm.fileExists(atPath: containerStore.path) else { return }

        do {
            try fm.copyItem(at: containerStore, to: destination)
            print("📦 Migrated shelf store from sandbox container to \(destination.path)")
        } catch {
            print("⚠️ Failed to migrate shelf store from sandbox container: \(error.localizedDescription)")
        }
    }

    func load() -> [ShelfItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        
        // Try to decode as array first (normal case)
        if let items = try? decoder.decode([ShelfItem].self, from: data) {
            return items
        }
        
        // If array decoding fails, try to decode individual items
        do {
            // Parse as JSON array to get individual item data
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                print("⚠️ Shelf persistence file is not a valid JSON array")
                return []
            }
            
            var validItems: [ShelfItem] = []
            var failedCount = 0
            
            for (index, jsonItem) in jsonArray.enumerated() {
                do {
                    let itemData = try JSONSerialization.data(withJSONObject: jsonItem)
                    let item = try decoder.decode(ShelfItem.self, from: itemData)
                    validItems.append(item)
                } catch {
                    failedCount += 1
                    print("⚠️ Failed to decode shelf item at index \(index): \(error.localizedDescription)")
                }
            }
            
            if failedCount > 0 {
                print("📦 Successfully loaded \(validItems.count) shelf items, discarded \(failedCount) corrupted items")
            }
            
            return validItems
        } catch {
            print("❌ Failed to parse shelf persistence file: \(error.localizedDescription)")
            return []
        }
    }

    func save(_ items: [ShelfItem]) {
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: Data.WritingOptions.atomic)
        } catch {
            print("Failed to save shelf items: \(error.localizedDescription)")
        }
    }
}
