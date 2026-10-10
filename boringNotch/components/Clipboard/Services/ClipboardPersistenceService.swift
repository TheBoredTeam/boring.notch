//
//  ClipboardPersistenceService.swift
//  boringNotch
//
//  Created by Claude on 2026-07-05.
//

import AppKit
import Foundation

final class ClipboardPersistenceService {
    static let shared = ClipboardPersistenceService()

    private let fileURL: URL
    let imagesDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        let dir = (support ?? fm.temporaryDirectory)
            .appendingPathComponent("boringNotch", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)
        imagesDirectory = dir.appendingPathComponent("Images", isDirectory: true)
        try? fm.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("items.json")
        encoder.outputFormatting = [.prettyPrinted]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([ClipboardItem].self, from: data)) ?? []
    }

    func save(_ items: [ClipboardItem]) {
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save clipboard items: \(error.localizedDescription)")
        }
    }

    // MARK: - Image storage

    func storeImage(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        let fileName = UUID().uuidString + ".png"
        do {
            try png.write(to: imagesDirectory.appendingPathComponent(fileName), options: .atomic)
            return fileName
        } catch {
            print("Failed to store clipboard image: \(error.localizedDescription)")
            return nil
        }
    }

    func loadImage(fileName: String) -> NSImage? {
        NSImage(contentsOf: imagesDirectory.appendingPathComponent(fileName))
    }

    func deleteImage(fileName: String) {
        try? FileManager.default.removeItem(
            at: imagesDirectory.appendingPathComponent(fileName))
    }

    /// Remove image files that no longer belong to any item.
    func pruneOrphanedImages(keeping items: [ClipboardItem]) {
        let referenced = Set(items.compactMap(\.imageFileName))
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: imagesDirectory.path) else { return }
        for file in files where !referenced.contains(file) {
            try? fm.removeItem(at: imagesDirectory.appendingPathComponent(file))
        }
    }
}
