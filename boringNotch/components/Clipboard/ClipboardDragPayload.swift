//
//  ClipboardDragPayload.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit

/// Chat editors consume one text value or a list of real files, rather than multiple raw images.
final class ClipboardDragPayload {
    let writers: [any NSPasteboardWriting]
    let previewItems: [ClipboardHistoryItem]
    private let exportDirectory: URL?
    private var finished = false
    private static let retentionInterval: TimeInterval = 24 * 60 * 60

    init(
        items: [ClipboardHistoryItem],
        exportRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("boringNotch-ClipboardDragExports", isDirectory: true)
    ) throws {
        let textItems = items.filter {
            if case .text = $0.content { return true }
            return false
        }
        let combinedText = textItems.compactMap { item -> String? in
            if case .text(let value, _) = item.content { return value }
            return nil
        }.joined(separator: "\n\n")

        if textItems.count == items.count {
            exportDirectory = nil
            previewItems = Array(items.prefix(1))
            if let first = items.first {
                let writer = NSPasteboardItem()
                writer.setString(combinedText, forType: .string)
                if items.count == 1, case .text(let value, true) = first.content {
                    writer.setString(value, forType: .URL)
                }
                writers = [writer]
            } else {
                writers = []
            }
            return
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: exportRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exportRoot.path)
        Self.removeExpiredExports(in: exportRoot)
        let directory = exportRoot.appendingPathComponent("drag-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
        )
        var prepared = false
        defer { if !prepared { try? fileManager.removeItem(at: directory) } }

        var fileURLs: [URL] = []
        var previews: [ClipboardHistoryItem] = []
        for item in items {
            let data: Data
            let fileExtension: String
            switch item.content {
            case .text:
                guard item.id == textItems.first?.id else { continue }
                data = Data(combinedText.utf8)
                fileExtension = "txt"
            case .image(let original, let type, _):
                data = original
                fileExtension = type == .png ? "png" : "tiff"
            }
            let filename = String(format: "%02d", fileURLs.count + 1) + "-Clipboard.\(fileExtension)"
            let url = directory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            fileURLs.append(url)
            previews.append(item)
        }
        // AppKit also exposes these URLs as the aggregate legacy filename list used by older chat drop handlers.
        let fileWriters = fileURLs.map { url in
            let writer = NSPasteboardItem()
            writer.setString(url.absoluteString, forType: .fileURL)
            return writer
        }
        writers = fileWriters
        previewItems = previews
        exportDirectory = directory
        prepared = true
    }

    /// Successful drops may remain unsent drafts, so their files survive the native drag session.
    func finish(completed: Bool) {
        guard !finished else { return }
        finished = true
        guard let directory = exportDirectory else { return }
        if completed {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: directory.path)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.retentionInterval) {
                try? FileManager.default.removeItem(at: directory)
            }
        } else {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    deinit {
        if !finished, let exportDirectory { try? FileManager.default.removeItem(at: exportDirectory) }
    }

    private static func removeExpiredExports(in root: URL) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: Array(keys)
        ) else { return }
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        for directory in directories where directory.lastPathComponent.hasPrefix("drag-") {
            guard let values = try? directory.resourceValues(forKeys: keys), values.isDirectory == true,
                  let modified = values.contentModificationDate, modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
