//
//  ClipboardPersistenceService.swift
//  boringNotch
//

import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Shared location

enum ClipboardStorage {
    /// Application Support/boringNotch/Clipboard — alongside the Shelf's own folder.
    static let directory: URL = {
        let fm = FileManager.default
        let support = try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = (support ?? fm.temporaryDirectory)
            .appendingPathComponent("boringNotch", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let blobsDirectory: URL = {
        let dir = directory.appendingPathComponent("Blobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

// MARK: - History file

/// Persists the clipboard history to a single JSON file.
///
/// Differs from `ShelfPersistenceService` in two deliberate ways, because clipboard capture is a
/// far hotter path than shelf drops:
///   - writes are **debounced** and run on a background queue rather than synchronously on main;
///   - output is compact rather than pretty-printed.
/// The defensive per-element `load()` fallback is copied from the Shelf, and matters more here:
/// a truncated write from a crash must not discard the whole history.
final class ClipboardPersistenceService: @unchecked Sendable {
    static let shared = ClipboardPersistenceService()

    /// Long enough that a burst of copies coalesces into one write, short enough that the window
    /// of loss on an unclean exit stays small. Clean exits go through `flush()`.
    private static let debounceInterval: TimeInterval = 0.75

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(
        label: "theboringteam.boringnotch.clipboard.persistence", qos: .utility)

    private let lock = NSLock()
    private var pendingWrite: DispatchWorkItem?
    private var pendingItems: [ClipboardItem]?

    private init() {
        fileURL = ClipboardStorage.directory.appendingPathComponent("history.json")
        // Not .prettyPrinted: nothing reads this by hand, and it roughly doubles size and encode cost.
        encoder.outputFormatting = []
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: Loading

    func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        if let items = try? decoder.decode([ClipboardItem].self, from: data) {
            return items
        }

        // Whole-array decode failed — salvage whatever individual entries still parse.
        do {
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                print("⚠️ Clipboard history file is not a valid JSON array")
                return []
            }

            var validItems: [ClipboardItem] = []
            var failedCount = 0

            for (index, jsonItem) in jsonArray.enumerated() {
                do {
                    let itemData = try JSONSerialization.data(withJSONObject: jsonItem)
                    validItems.append(try decoder.decode(ClipboardItem.self, from: itemData))
                } catch {
                    failedCount += 1
                    print("⚠️ Failed to decode clipboard item at index \(index): \(error.localizedDescription)")
                }
            }

            if failedCount > 0 {
                print("📋 Loaded \(validItems.count) clipboard items, discarded \(failedCount) corrupted")
            }

            return validItems
        } catch {
            print("❌ Failed to parse clipboard history file: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: Saving

    /// Coalescing, debounced save. Safe to call on every mutation.
    func scheduleSave(_ items: [ClipboardItem]) {
        lock.lock()
        pendingItems = items
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.writePending()
        }
        pendingWrite = work
        lock.unlock()

        queue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    /// Writes any pending snapshot synchronously. Must be called from `applicationWillTerminate`,
    /// otherwise the last debounce window's captures are lost on quit.
    func flush() {
        lock.lock()
        pendingWrite?.cancel()
        pendingWrite = nil
        let items = pendingItems
        pendingItems = nil
        lock.unlock()

        guard let items else { return }
        write(items)
    }

    private func writePending() {
        lock.lock()
        let items = pendingItems
        pendingItems = nil
        pendingWrite = nil
        lock.unlock()

        guard let items else { return }
        write(items)
    }

    private func write(_ items: [ClipboardItem]) {
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("❌ Failed to save clipboard history: \(error.localizedDescription)")
        }
    }
}

// MARK: - Image blobs

/// Stores copied images on disk: one full-fidelity file for faithful re-copy, and one small
/// thumbnail so scrolling a long history never decodes full-resolution screenshots.
final class ClipboardBlobStore: @unchecked Sendable {
    static let shared = ClipboardBlobStore()

    /// Above this, the image is not recorded at all rather than silently stored in part.
    static let maxImageBytes = 20 * 1024 * 1024
    private static let thumbnailMaxDimension: CGFloat = 128

    private init() {}

    func url(forFileName fileName: String) -> URL {
        ClipboardStorage.blobsDirectory.appendingPathComponent(fileName)
    }

    /// Writes `data` plus a downscaled thumbnail. Returns nil if the payload is over the size cap
    /// or cannot be written.
    func write(imageData: Data, uti: String) -> ClipboardBlobRef? {
        guard imageData.count <= Self.maxImageBytes else {
            print("⚠️ Skipping clipboard image of \(imageData.count) bytes (over cap)")
            return nil
        }

        let base = UUID().uuidString
        let ext = (uti == UTType.tiff.identifier) ? "tiff" : "png"
        let fileName = "\(base).\(ext)"

        do {
            try imageData.write(to: url(forFileName: fileName), options: .atomic)
        } catch {
            print("❌ Failed to write clipboard image blob: \(error.localizedDescription)")
            return nil
        }

        let rep = NSBitmapImageRep(data: imageData)
        let pixelWidth = rep?.pixelsWide
        let pixelHeight = rep?.pixelsHigh

        var thumbFileName: String?
        if let thumbData = makeThumbnail(from: imageData) {
            let name = "\(base)_thumb.png"
            do {
                try thumbData.write(to: url(forFileName: name), options: .atomic)
                thumbFileName = name
            } catch {
                print("⚠️ Failed to write clipboard thumbnail: \(error.localizedDescription)")
            }
        }

        return ClipboardBlobRef(
            fileName: fileName,
            thumbFileName: thumbFileName,
            utiIdentifier: uti,
            byteCount: imageData.count,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    private func makeThumbnail(from data: Data) -> Data? {
        guard let source = NSBitmapImageRep(data: data) else { return nil }

        let width = CGFloat(source.pixelsWide)
        let height = CGFloat(source.pixelsHigh)
        guard width > 0, height > 0 else { return nil }

        let scale = min(1, Self.thumbnailMaxDimension / max(width, height))
        let targetSize = NSSize(width: floor(width * scale), height: floor(height * scale))
        guard targetSize.width >= 1, targetSize.height >= 1 else { return nil }

        let target = NSImage(size: targetSize)
        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: targetSize))
        target.unlockFocus()

        guard let tiff = target.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    func delete(_ ref: ClipboardBlobRef) {
        let fm = FileManager.default
        try? fm.removeItem(at: url(forFileName: ref.fileName))
        if let thumb = ref.thumbFileName {
            try? fm.removeItem(at: url(forFileName: thumb))
        }
    }

    func deleteBlobs(of item: ClipboardItem) {
        guard case .image(let ref) = item.kind else { return }
        delete(ref)
    }

    /// Removes blob files no longer referenced by the history. Guards against leaking files when
    /// the app dies between trimming the array and deleting the blob.
    func garbageCollect(keeping referenced: Set<String>) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: ClipboardStorage.blobsDirectory, includingPropertiesForKeys: nil) else { return }

        var removed = 0
        for file in contents where !referenced.contains(file.lastPathComponent) {
            try? fm.removeItem(at: file)
            removed += 1
        }
        if removed > 0 {
            print("🧹 Reclaimed \(removed) orphaned clipboard blob(s)")
        }
    }

    /// Total bytes occupied by blobs, for display in Settings.
    func totalBytesOnDisk() -> Int {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: ClipboardStorage.blobsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }

        return contents.reduce(into: 0) { total, url in
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
    }
}

// MARK: - Referenced blob names

extension Array where Element == ClipboardItem {
    /// Every blob file name the history currently points at, for garbage collection.
    var referencedBlobFileNames: Set<String> {
        var names: Set<String> = []
        for item in self {
            guard case .image(let ref) = item.kind else { continue }
            names.insert(ref.fileName)
            if let thumb = ref.thumbFileName { names.insert(thumb) }
        }
        return names
    }
}
