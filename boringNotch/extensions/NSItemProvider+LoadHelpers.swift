//
//  NSItemProvider+LoadHelpers.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//


import AppKit
import Foundation
import UniformTypeIdentifiers

extension NSItemProvider {
    
    func extractItem() async -> URL? {
        return await loadFileURL(typeIdentifier: UTType.item.identifier)
    }

    
    /// Detects if this is a file dragged from the filesystem
    func extractFileURL() async -> URL? {
        if hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await loadFileURL(typeIdentifier: UTType.fileURL.identifier)
        }
        return nil
    }
    
    /// Loads raw data for the given type identifier
    func loadData() async -> Data? {
        NSLog(String(describing: self.registeredTypeIdentifiers))
        guard hasItemConformingToTypeIdentifier(UTType.data.identifier) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { item, error in
                if let error = error {
                    print("Error loading data for type \(UTType.data.identifier): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                    return
                }
                if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    if !url.absoluteString.contains("com.apple.SwiftUI.filePromises") {
                        cont.resume(returning: nil)
                        return
                    }
                    self.suggestedName = self.suggestedName ?? url.lastPathComponent
                    
                    let fileManager = FileManager.default
                    let folderURL = url.deletingLastPathComponent()

                    do {
                        // Delete the file first
                        try fileManager.removeItem(at: url)
                        print("Deleted file: \(url.path)")

                        // Check folder contents
                        let contents = try fileManager.contentsOfDirectory(atPath: folderURL.path)
                        if contents.isEmpty {
                            try fileManager.removeItem(at: folderURL)
                            print("Folder was empty, deleted folder: \(folderURL.path)")
                        } else {
                            print("Folder not deleted — it still contains \(contents.count) item(s).")
                        }

                    } catch {
                        print("Error: \(error.localizedDescription)")
                    }
                    
                    cont.resume(returning: data)
                } else if let data = item as? Data {
                    cont.resume(returning: data)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Fulfills a file promise (e.g. an attachment dragged out of Mail, Spark, Outlook,
    /// or Messages) by asking the provider to write its bytes to disk via
    /// `loadFileRepresentation(forTypeIdentifier:)`, then copies the result into the
    /// app's own temp area before the system reclaims the original temp file.
    func extractPromisedFile() async -> URL? {
        guard let typeIdentifier = bestPromisedTypeIdentifier() else { return nil }

        return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            self.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error = error {
                    print("❌ Error fulfilling file promise for type \(typeIdentifier): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                    return
                }
                guard let url = url else {
                    cont.resume(returning: nil)
                    return
                }

                // The provided URL points at a system-owned temp file that is deleted the
                // instant this handler returns, so copy it synchronously into our own temp area.
                let filename = self.suggestedName ?? url.lastPathComponent
                let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
                let dirURL = tempDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
                let destURL = dirURL.appendingPathComponent(filename)

                do {
                    try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: destURL)
                    cont.resume(returning: destURL)
                } catch {
                    print("❌ Error copying fulfilled file promise: \(error.localizedDescription)")
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Selects the most specific concrete content type to fulfill a file promise with,
    /// excluding transport/abstract identifiers. Falls back to `public.data` if the
    /// provider only advertises the generic type.
    private func bestPromisedTypeIdentifier() -> String? {
        let excluded: Set<String> = [
            UTType.url.identifier,
            UTType.fileURL.identifier,
            UTType.plainText.identifier,
            UTType.utf8PlainText.identifier,
            "com.apple.pasteboard.promised-file-url",
        ]

        let candidates = registeredTypeIdentifiers.filter { !excluded.contains($0) }

        // Prefer a concrete type that conforms to data/content/item.
        if let concrete = candidates.first(where: { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .data) || type.conforms(to: .content) || type.conforms(to: .item)
        }) {
            return concrete
        }

        // Fall back to the generic data type if the provider advertises nothing more specific.
        if hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            return UTType.data.identifier
        }

        return nil
    }

    /// Attempts to extract a URL (web link) from the provider
    func extractURL() async -> URL? {
        if self.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(typeIdentifier: UTType.url.identifier) {
                //Validate URL
                guard url.scheme != nil else { return nil }
                return url
            }
        }

        return nil
    }

    func extractText() async -> String? {
        let textTypes = [UTType.utf8PlainText.identifier, UTType.plainText.identifier]

        for typeIdentifier in textTypes where self.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let text = await loadText(typeIdentifier: typeIdentifier) {
                return text
            }
        }

        return nil
    }

    /// Loads a file URL from the provider for the given type identifier.
    func loadFileURL(typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error = error {
                    print("❌ Error loading item for type \(typeIdentifier): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                    return
                }
                var resolvedURL: URL?
                if let url = item as? URL {
                    // Direct URL provided
                    resolvedURL = url
                } else if let data = item as? Data {
                    // Some providers hand out a UTF-8 file URL string, others a bookmark. Prefer parsing string first.
                    if let string = String(data: data, encoding: .utf8) {
                        if let url = URL(string: string) {
                            resolvedURL = url
                        } else if string.hasPrefix("/") {
                            // Plain file system path
                            resolvedURL = URL(fileURLWithPath: string)
                        }
                    }
                    if resolvedURL == nil {
                        // Fallback: try treating the data as a bookmark
                        let bookmark = Bookmark(data: data)
                        resolvedURL = bookmark.resolvedURL
                    }
                } else if let string = item as? String {
                    if let url = URL(string: string) {
                        resolvedURL = url
                    } else if string.hasPrefix("/") {
                        resolvedURL = URL(fileURLWithPath: string)
                    }
                }
                cont.resume(returning: resolvedURL)
            }
        }
    }

    /// Loads a URL from the provider for the given type identifier.
    func loadURL(typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    cont.resume(returning: nil)
                    return
                }

                if let url = item as? URL {
                    cont.resume(returning: url)
                } else if let data = item as? Data {
                    if let string = String(data: data, encoding: .utf8) {
                        if let url = URL(string: string) {
                            cont.resume(returning: url)
                            return
                        } else if string.hasPrefix("/") {
                            cont.resume(returning: URL(fileURLWithPath: string))
                            return
                        }
                    }
                    cont.resume(returning: nil)
                } else if let string = item as? String {
                    if let url = URL(string: string) {
                        cont.resume(returning: url)
                    } else if string.hasPrefix("/") {
                        cont.resume(returning: URL(fileURLWithPath: string))
                    } else {
                        cont.resume(returning: nil)
                    }
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Loads text from the provider for the given type identifier.
    func loadText(typeIdentifier: String) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    cont.resume(returning: nil)
                    return
                }

                if let string = item as? String {
                    cont.resume(returning: string)
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8) {
                    cont.resume(returning: string)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
