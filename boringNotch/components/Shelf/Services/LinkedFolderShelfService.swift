//
//  LinkedFolderShelfService.swift
//  boringNotch
//
//  Created by Codex on 2025-10-11.
//

import AppKit
import Foundation

enum LinkedFolderShelfService {
    static func loadItems(from bookmarkData: Data, limit: Int) async -> [ShelfItem] {
        guard limit > 0 else { return [] }

        let bookmark = Bookmark(data: bookmarkData)
        guard let folderURL = bookmark.resolveURL() else { return [] }

        return await folderURL.accessSecurityScopedResource { accessibleURL in
            let keys: Set<URLResourceKey> = [
                .contentModificationDateKey,
                .creationDateKey,
                .isDirectoryKey
            ]
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]

            let urls = (try? FileManager.default.contentsOfDirectory(
                at: accessibleURL,
                includingPropertiesForKeys: Array(keys),
                options: options
            )) ?? []

            let sorted = urls.sorted { lhs, rhs in
                let lhsDate = resourceDate(for: lhs)
                let rhsDate = resourceDate(for: rhs)
                if lhsDate == rhsDate {
                    return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
                }
                return lhsDate > rhsDate
            }

            var results: [ShelfItem] = []
            results.reserveCapacity(min(sorted.count, limit))

            for url in sorted.prefix(limit) {
                if let bookmark = try? Bookmark(url: url) {
                    let item = await MainActor.run {
                        ShelfItem(kind: .file(bookmark: bookmark.data))
                    }
                    results.append(item)
                }
            }

            return results
        }
    }

    static func saveItems(from providers: [NSItemProvider], to bookmarkData: Data) async {
        guard !providers.isEmpty else { return }
        let bookmark = Bookmark(data: bookmarkData)
        guard let folderURL = bookmark.resolveURL() else { return }

        _ = await folderURL.accessSecurityScopedResource { accessibleURL in
            for provider in providers {
                await saveProvider(provider, to: accessibleURL)
            }
        }
    }

    private static func resourceDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.contentModificationDate ?? values?.creationDate ?? Date.distantPast
    }

    private static func saveProvider(_ provider: NSItemProvider, to folderURL: URL) async {
        if let actualFileURL = await provider.extractFileURL() {
            await copyFileURL(actualFileURL, to: folderURL)
            return
        }

        if let url = await provider.extractURL() {
            if url.isFileURL {
                await copyFileURL(url, to: folderURL)
            } else {
                saveWebloc(url, to: folderURL)
            }
            return
        }

        if let text = await provider.extractText() {
            saveText(text, suggestedName: provider.suggestedName, to: folderURL)
            return
        }

        if let data = await provider.loadData() {
            saveData(data, suggestedName: provider.suggestedName, to: folderURL)
            return
        }

        if let fileURL = await provider.extractItem() {
            await copyFileURL(fileURL, to: folderURL)
        }
    }

    private static func copyFileURL(_ fileURL: URL, to folderURL: URL) async {
        let destURL = uniqueDestinationURL(
            in: folderURL,
            baseName: fileURL.deletingPathExtension().lastPathComponent,
            ext: fileURL.pathExtension
        )

        _ = fileURL.accessSecurityScopedResource { accessibleURL in
            do {
                if accessibleURL.standardizedFileURL == destURL.standardizedFileURL {
                    try FileManager.default.setAttributes(
                        [.modificationDate: Date()],
                        ofItemAtPath: destURL.path
                    )
                } else {
                    try FileManager.default.copyItem(at: accessibleURL, to: destURL)
                    try FileManager.default.setAttributes(
                        [.modificationDate: Date()],
                        ofItemAtPath: destURL.path
                    )
                }
            } catch {
                print("Failed to copy \(accessibleURL.path) to linked folder: \(error)")
            }
        }
    }

    private static func saveText(_ text: String, suggestedName: String?, to folderURL: URL) {
        let baseName = baseName(from: suggestedName, fallback: "Text")
        let destURL = uniqueDestinationURL(in: folderURL, baseName: baseName, ext: "txt")
        do {
            try text.write(to: destURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: destURL.path
            )
        } catch {
            print("Failed to save text to linked folder: \(error)")
        }
    }

    private static func saveData(_ data: Data, suggestedName: String?, to folderURL: URL) {
        let fallback = "Dropped Item"
        let name = suggestedName?.isEmpty == false ? suggestedName! : fallback
        let nameURL = URL(fileURLWithPath: name)
        let baseName = nameURL.deletingPathExtension().lastPathComponent
        let ext = nameURL.pathExtension.isEmpty ? "dat" : nameURL.pathExtension
        let destURL = uniqueDestinationURL(in: folderURL, baseName: baseName, ext: ext)
        do {
            try data.write(to: destURL)
            try FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: destURL.path
            )
        } catch {
            print("Failed to save data to linked folder: \(error)")
        }
    }

    private static func saveWebloc(_ url: URL, to folderURL: URL) {
        let baseName = baseName(from: url.host, fallback: "Link")
        let destURL = uniqueDestinationURL(in: folderURL, baseName: baseName, ext: "webloc")
        let weblocContent = createWeblocContent(for: url)
        guard let data = weblocContent.data(using: .utf8) else { return }
        do {
            try data.write(to: destURL)
            try FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: destURL.path
            )
        } catch {
            print("Failed to save link to linked folder: \(error)")
        }
    }

    private static func createWeblocContent(for url: URL) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>URL</key>
            <string>\(url.absoluteString)</string>
        </dict>
        </plist>
        """
    }

    private static func baseName(from name: String?, fallback: String) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed! : fallback
    }

    private static func uniqueDestinationURL(in folderURL: URL, baseName: String, ext: String) -> URL {
        let initial = ext.isEmpty
            ? folderURL.appendingPathComponent(baseName)
            : folderURL.appendingPathComponent(baseName).appendingPathExtension(ext)
        var candidate = initial
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        var counter = 2
        while true {
            let newName = "\(baseName) \(counter)"
            candidate = ext.isEmpty
                ? folderURL.appendingPathComponent(newName)
                : folderURL.appendingPathComponent(newName).appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
