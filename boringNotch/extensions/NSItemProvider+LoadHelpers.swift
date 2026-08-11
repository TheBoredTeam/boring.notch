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
        guard hasItemConformingToTypeIdentifier(UTType.data.identifier) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { item, error in
                if let error = error {
                    print("Error loading data for type \(UTType.data.identifier): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                    return
                }
                if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    // Requesting the generic "public.data" representation commonly
                    // makes the system write a temp file and hand back its URL —
                    // for BOTH SwiftUI's own drag mechanism AND external system
                    // drag sources (the screenshot thumbnail bubble, Quick Look
                    // previews, browser image drags, etc). Previously this only
                    // accepted SwiftUI's own temp path and silently discarded
                    // every external source's data, even though it had already
                    // been read successfully above.
                    self.suggestedName = self.suggestedName ?? url.lastPathComponent

                    // Best-effort cleanup of the system's temp file/folder — not
                    // gating the actual data return on it succeeding.
                    let fileManager = FileManager.default
                    let folderURL = url.deletingLastPathComponent()
                    try? fileManager.removeItem(at: url)
                    if let contents = try? fileManager.contentsOfDirectory(atPath: folderURL.path),
                       contents.isEmpty {
                        try? fileManager.removeItem(at: folderURL)
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
