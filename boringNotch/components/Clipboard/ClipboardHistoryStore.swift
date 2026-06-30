//
//  ClipboardHistoryStore.swift
//  boringNotch
//

import AppKit
import Foundation
import ImageIO

final class ClipboardHistoryStore {
    static let shared = ClipboardHistoryStore()

    let directoryURL: URL
    let imagesDirectoryURL: URL
    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "ai.minitap.clipboard-history-store", qos: .utility)
    private let fileManager = FileManager.default

    private init() {
        let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        directoryURL = (support ?? fileManager.temporaryDirectory)
            .appendingPathComponent("boringNotch", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)
        imagesDirectoryURL = directoryURL.appendingPathComponent("Images", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("history.json")

        try? fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
    }

    func load() -> [ClipboardHistoryItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ClipboardHistoryItem].self, from: data)) ?? []
    }

    func save(_ items: [ClipboardHistoryItem]) {
        let snapshot = items
        ioQueue.async { [directoryURL, fileURL, fileManager] in
            Self.save(snapshot, directoryURL: directoryURL, fileURL: fileURL, fileManager: fileManager)
        }
    }

    func flushPendingSaves() {
        ioQueue.sync { }
    }

    private static func save(_ items: [ClipboardHistoryItem], directoryURL: URL, fileURL: URL, fileManager: FileManager) {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save clipboard history: \(error.localizedDescription)")
        }
    }

    func storeImageData(_ data: Data, filename: String) -> String? {
        let safeFilename = filename.hasSuffix(".png") ? filename : "\(filename).png"
        let url = imagesDirectoryURL.appendingPathComponent(safeFilename)
        do {
            try fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return safeFilename
        } catch {
            print("Failed to store clipboard image: \(error.localizedDescription)")
            return nil
        }
    }

    func imageURL(for item: ClipboardHistoryItem) -> URL? {
        guard let filename = item.imageFilename else { return nil }
        return imagesDirectoryURL.appendingPathComponent(filename)
    }

    func imageData(for item: ClipboardHistoryItem) -> Data? {
        guard let url = imageURL(for: item) else { return nil }
        return try? Data(contentsOf: url)
    }

    func imageExists(for item: ClipboardHistoryItem) -> Bool {
        guard let url = imageURL(for: item) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    func thumbnail(for item: ClipboardHistoryItem, maxPixelSize: Int) -> NSImage? {
        guard let url = imageURL(for: item),
              let source = CGImageSourceCreateWithURL(
                url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func removeImage(for item: ClipboardHistoryItem) {
        guard let url = imageURL(for: item) else { return }
        try? fileManager.removeItem(at: url)
    }

    func removeImage(named filename: String) {
        let url = imagesDirectoryURL.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }

    func pruneOrphanedImages(keeping items: [ClipboardHistoryItem]) {
        let keep = Set(items.compactMap(\.imageFilename))
        guard let files = try? fileManager.contentsOfDirectory(at: imagesDirectoryURL, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files where !keep.contains(file.lastPathComponent) {
            try? fileManager.removeItem(at: file)
        }
    }

    func storageByteCount() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(
            at: imagesDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + size
        }
    }

    func clearAll() {
        ioQueue.sync { [fileURL, imagesDirectoryURL, fileManager] in
            try? fileManager.removeItem(at: fileURL)
            try? fileManager.removeItem(at: imagesDirectoryURL)
            try? fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
        }
    }
}
