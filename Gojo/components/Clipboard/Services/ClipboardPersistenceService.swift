import AppKit
import Foundation

/// Stores clipboard image blobs as PNG files alongside history.json so the
/// JSON history only carries lightweight references.
final class ClipboardImageStore {
    static let shared = ClipboardImageStore()

    private let directory: URL
    private let pruneQueue = DispatchQueue(label: "rohoswagger.gojo.clipboard-image-prune", qos: .utility)
    private let thumbnailCache = NSCache<NSString, NSImage>()

    // Files younger than this are never pruned, so an in-flight capture can't
    // be deleted by a prune pass that was scheduled before it was saved.
    private static let pruneMinimumAge: TimeInterval = 5 * 60

    private init() {
        let fileManager = FileManager.default
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        directory = appSupport
            .appendingPathComponent("Gojo", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        thumbnailCache.countLimit = 200
        thumbnailCache.totalCostLimit = 64 * 1024 * 1024
    }

    func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    func save(_ data: Data, named fileName: String) -> Bool {
        do {
            try data.write(to: url(for: fileName), options: .atomic)
            return true
        } catch {
            NSLog("ClipboardImageStore.save failed: %@", error.localizedDescription)
            return false
        }
    }

    func loadData(named fileName: String) -> Data? {
        try? Data(contentsOf: url(for: fileName))
    }

    func delete(named fileName: String) {
        let target = url(for: fileName)
        // Cache keys are per-size composites; deletes are rare enough that
        // dropping the whole cache is simpler than tracking keys per file.
        thumbnailCache.removeAllObjects()
        pruneQueue.async {
            try? FileManager.default.removeItem(at: target)
        }
    }

    /// Removes image files no longer referenced by any history item, e.g.
    /// after entry-limit eviction or deduplicated captures.
    func pruneOrphans(keeping fileNames: Set<String>) {
        let directory = directory
        pruneQueue.async {
            let fileManager = FileManager.default
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return }

            let cutoff = Date().addingTimeInterval(-Self.pruneMinimumAge)
            for url in urls where !fileNames.contains(url.lastPathComponent) {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified > cutoff { continue }
                try? fileManager.removeItem(at: url)
            }
        }
    }

    /// Cached thumbnail only — never touches disk, safe to call from `body`.
    func cachedThumbnail(named fileName: String, maxPixelSize: CGFloat) -> NSImage? {
        thumbnailCache.object(forKey: Self.cacheKey(fileName: fileName, maxPixelSize: maxPixelSize))
    }

    /// Downsampled image for display, cached per file + size.
    func thumbnail(named fileName: String, maxPixelSize: CGFloat) -> NSImage? {
        let cacheKey = Self.cacheKey(fileName: fileName, maxPixelSize: maxPixelSize)
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }

        guard let source = CGImageSourceCreateWithURL(url(for: fileName) as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnailCache.setObject(image, forKey: cacheKey, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    private static func cacheKey(fileName: String, maxPixelSize: CGFloat) -> NSString {
        "\(fileName)#\(Int(maxPixelSize))" as NSString
    }
}

final class ClipboardPersistenceService {
    static let shared = ClipboardPersistenceService()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let fileManager = FileManager.default
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let directory = appSupport
            .appendingPathComponent("Gojo", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        fileURL = directory.appendingPathComponent("history.json")
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Returns nil when the history file exists but could not be read or
    /// decoded — callers must not treat that as an empty history (e.g. by
    /// pruning image blobs against it).
    func load() -> [ClipboardItem]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        if let items = try? decoder.decode([ClipboardItem].self, from: data) {
            return items
        }
        // Salvage what decodes; drop only the malformed entries.
        if let partial = try? decoder.decode([FailableClipboardItem].self, from: data) {
            return partial.compactMap(\.item)
        }
        return nil
    }

    func save(_ items: [ClipboardItem]) {
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("ClipboardPersistenceService.save failed: %@", error.localizedDescription)
        }
    }
}

private struct FailableClipboardItem: Decodable {
    let item: ClipboardItem?

    init(from decoder: Decoder) throws {
        item = try? ClipboardItem(from: decoder)
    }
}
