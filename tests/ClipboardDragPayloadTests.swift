import AppKit

/// Synthetic fixtures and a named pasteboard keep the user's clipboard untouched.
@main
@MainActor
struct ClipboardDragPayloadTests {
    private static var assertions = 0
    private static let source = ClipboardSourceApplication(name: "Synthetic App", bundleIdentifier: nil)

    static func main() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-drag-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let text = "First original line\nSecond original line"
        let url = "https://example.com/a?query=synthetic#section"
        let png = imageData(type: .png)
        let tiff = imageData(type: .tiff)
        let items = [
            ClipboardHistoryItem(content: .text(text, isURL: false), source: source),
            ClipboardHistoryItem(content: .text(url, isURL: true), source: source),
            imageItem(png, type: .png),
            imageItem(tiff, type: .tiff)
        ]
        let exportRoot = directory.appendingPathComponent("exports", isDirectory: true)
        let texts = try ClipboardDragPayload(items: Array(items.prefix(2)), exportRoot: exportRoot)
        expect(texts.writers.count == 1, "Multiple text entries become one text representation")
        expect(texts.previewItems.map(\.id) == [items[0].id], "Combined text uses its first card as the preview")
        expect(board.writeObjects(texts.writers), "Write combined text to an isolated pasteboard")
        expect(board.string(forType: .string) == text + "\n\n" + url, "Single-value consumers receive every selected text block in order")
        expect(board.string(forType: .URL) == nil, "Combined text does not claim to be a single URL")
        expect(!FileManager.default.fileExists(atPath: exportRoot.path), "Text-only dragging does not create exported files")
        texts.finish(completed: true)

        let singleURL = try ClipboardDragPayload(items: [items[1]], exportRoot: exportRoot)
        board.clearContents()
        expect(board.writeObjects(singleURL.writers), "Write a single URL selection")
        expect(board.string(forType: .URL) == url, "A single URL keeps its native URL representation")
        expect(board.string(forType: .string) == url, "A single URL also remains plain text")
        singleURL.finish(completed: false)

        let imageItems = Array(items.suffix(2))
        let images = try ClipboardDragPayload(items: imageItems, exportRoot: exportRoot)
        board.clearContents()
        expect(board.writeObjects(images.writers), "Write both image files to the drag pasteboard")
        let imageURLs = fileURLs(from: board)
        expect(imageURLs.count == 2, "NSURL-based consumers receive every selected image")
        expect(images.previewItems.map(\.id) == imageItems.map(\.id), "Image previews retain selection order")
        expect(imageURLs.map(\.pathExtension) == ["png", "tiff"], "Image filenames preserve each original format")
        try expect(Data(contentsOf: imageURLs[0]) == png, "PNG export contains the exact original bytes")
        try expect(Data(contentsOf: imageURLs[1]) == tiff, "TIFF export contains the exact original bytes")
        expect(board.propertyList(forType: filenamesType) as? [String] == imageURLs.map(\.path), "Legacy file-list consumers receive every image path in order")
        expect(board.types?.contains(filenamesType) == true, "Legacy consumers discover the aggregate filename type before reading it")
        expect(board.data(forType: .png) == nil && board.data(forType: .tiff) == nil, "The batch cannot fall back to a receiver's single raw image path")
        try expect(permissions(at: exportRoot) == 0o700, "Export root is accessible only by its owner")
        try expect(permissions(at: imageURLs[0].deletingLastPathComponent()) == 0o700, "Each drag directory is accessible only by its owner")
        try expect(permissions(at: imageURLs[0]) == 0o600, "Exported image is readable and writable only by its owner")
        images.finish(completed: false)
        expect(imageURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }, "Canceling a drag removes all exported files immediately")

        let mixedItems = [items[2], items[0], items[3], items[1]]
        var mixed: ClipboardDragPayload? = try ClipboardDragPayload(items: mixedItems, exportRoot: exportRoot)
        board.clearContents()
        expect(board.writeObjects(mixed!.writers), "Write a mixed selection using real files")
        let mixedURLs = fileURLs(from: board)
        expect(mixedURLs.count == 3, "Mixed selection contains both images and one combined text attachment")
        expect(mixed!.previewItems.map(\.id) == [items[2].id, items[0].id, items[3].id], "Text bundle occupies the first text card's position among images")
        expect(mixedURLs.map(\.pathExtension) == ["png", "txt", "tiff"], "Mixed file ordering follows the selected cards")
        try expect(Data(contentsOf: mixedURLs[0]) == png, "Mixed PNG export remains lossless")
        try expect(String(contentsOf: mixedURLs[1], encoding: .utf8) == text + "\n\n" + url, "Mixed drop preserves all text in a UTF-8 attachment")
        try expect(Data(contentsOf: mixedURLs[2]) == tiff, "Mixed TIFF export remains lossless")
        expect(board.propertyList(forType: filenamesType) as? [String] == mixedURLs.map(\.path), "Legacy consumers receive all mixed attachment paths")
        try expect(permissions(at: mixedURLs[1]) == 0o600, "Exported text is accessible only by its owner")
        mixed!.finish(completed: true)
        mixed!.finish(completed: false)
        mixed = nil
        expect(mixedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "Successful drops survive source cleanup and repeated finish calls for unsent drafts")

        var abandoned: ClipboardDragPayload? = try ClipboardDragPayload(items: imageItems, exportRoot: exportRoot)
        board.clearContents()
        expect(board.writeObjects(abandoned!.writers), "Prepare an abandoned image drag")
        let abandonedURLs = fileURLs(from: board)
        expect(Set(abandonedURLs).isDisjoint(with: Set(mixedURLs)), "Separate drags use separate export directories")
        abandoned = nil
        expect(abandonedURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }, "Discarding an unfinished payload removes its exports")

        let stale = exportRoot.appendingPathComponent("drag-expired", isDirectory: true)
        let unrelated = exportRoot.appendingPathComponent("unrelated", isDirectory: true)
        for path in [stale, unrelated] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-25 * 60 * 60)], ofItemAtPath: path.path)
        }
        let cleanup = try ClipboardDragPayload(items: imageItems, exportRoot: exportRoot)
        expect(!FileManager.default.fileExists(atPath: stale.path), "A later drag removes exports older than 24 hours after a previous process exits")
        expect(FileManager.default.fileExists(atPath: unrelated.path), "Stale cleanup ignores directories it does not own")
        expect(mixedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "Stale cleanup preserves recent successful drafts")
        cleanup.finish(completed: false)
        print("Clipboard drag payloads: \(assertions) assertions passed using original synthetic data and an isolated pasteboard.")
    }

    private static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    private static func fileURLs(from board: NSPasteboard) -> [URL] {
        let objects = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        return (objects as? [NSURL] ?? []).map { $0 as URL }
    }

    private static func permissions(at url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private static func imageItem(_ data: Data, type: NSPasteboard.PasteboardType) -> ClipboardHistoryItem {
        ClipboardHistoryItem(content: .image(data, type: type, thumbnail: NSImage(size: NSSize(width: 1, height: 1))), source: source)
    }

    private static func imageData(type: NSBitmapImageRep.FileType) -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 8, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { fatalError("Could not create synthetic image") }
        let white = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
        let black = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        for x in 0..<16 {
            for y in 0..<8 {
                bitmap.setColor(x.isMultiple(of: 2) ? white : black, atX: x, y: y)
            }
        }
        guard let data = bitmap.representation(using: type, properties: [:]) else {
            fatalError("Could not encode synthetic image")
        }
        return data
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ label: String) rethrows {
        assertions += 1
        let passed = try condition()
        precondition(passed, label)
    }
}
