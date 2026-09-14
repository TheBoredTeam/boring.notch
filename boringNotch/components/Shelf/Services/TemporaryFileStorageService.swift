//
//  TemporaryFileStorageService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

enum TempFileType {
    case data(Data, suggestedName: String?)
    case text(String)
    case url(URL)
}

final class TemporaryFileStorageService: @unchecked Sendable {
    static let shared = TemporaryFileStorageService()

    private let baseDirectory: URL

    init(baseDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)) {
        self.baseDirectory = baseDirectory
    }
    
    // MARK: - Public Interface
    
    /// Creates a temporary file and tracks it for manual cleanup
    func createTempFile(for type: TempFileType) async -> URL? {
        return await withCheckedContinuation { continuation in
            let result = createTempFile(for: type)
            continuation.resume(returning: result)
        }
    }
    
    func removeTemporaryFileIfNeeded(at url: URL) {
        let standardizedURL = url.standardizedFileURL
        let standardizedBase = baseDirectory.standardizedFileURL
        guard standardizedURL.pathComponents.starts(with: standardizedBase.pathComponents) else {
            Log.shelf.debug("Attempted to remove temporary file outside temp directory: \(url.path)")
            return
        }

        let folderURL = standardizedURL.deletingLastPathComponent()

        do {
            try FileManager.default.removeItem(at: standardizedURL)
            Log.shelf.debug("Deleted file: \(standardizedURL.path)")

            let contents = try FileManager.default.contentsOfDirectory(atPath: folderURL.path)
            if contents.isEmpty {
                try FileManager.default.removeItem(at: folderURL)
                Log.shelf.debug("Folder was empty, deleted folder: \(folderURL.path)")
            } else {
                Log.shelf.debug("Folder not deleted — it still contains \(contents.count) item(s).")
            }

        } catch {
            Log.shelf.error("Error: \(error.localizedDescription)")
        }
    }

    /// Copies a callback-scoped provider representation into storage owned by the app.
    /// The copy is synchronous so the source is never used after the provider callback returns.
    func copyProviderFile(at sourceURL: URL, suggestedName: String?) -> URL? {
        let directoryURL = makeUniqueDirectory()
        let filename = safeFilename(
            suggestedName,
            fallback: sourceURL.lastPathComponent
        )
        let destinationURL = directoryURL.appendingPathComponent(filename, isDirectory: false)

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            Log.shelf.error("Failed to copy provider file: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Private Implementation
    
    private func createTempFile(for type: TempFileType) -> URL? {
        let uuid = UUID().uuidString
        
        switch type {
        case .data(let data, let suggestedName):
            let filename = safeFilename(suggestedName, fallback: "Untitled.dat")
            let dirURL = makeUniqueDirectory()
            let fileURL = dirURL.appendingPathComponent(filename)
            
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try data.write(to: fileURL)
                return fileURL
            } catch {
                Log.shelf.error("Error: \(error)")
                return nil
            }
            
        case .text(let string):
            let filename = "\(uuid).txt"
            let dirURL = makeUniqueDirectory()
            let fileURL = dirURL.appendingPathComponent(filename)
            
            guard let data = string.data(using: .utf8) else {
                Log.shelf.error("❌ Failed to convert text to data")
                return nil
            }
            
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try data.write(to: fileURL)
                return fileURL
            } catch {
                Log.shelf.error("Error: \(error)")
                return nil
            }
            
        case .url(let url):
            let filename = "\(url.host ?? uuid).webloc"
            let dirURL = makeUniqueDirectory()
            let fileURL = dirURL.appendingPathComponent(filename)
            
            let weblocContent = createWeblocContent(for: url)
            guard let data = weblocContent.data(using: String.Encoding.utf8) else {
                Log.shelf.error("❌ Failed to create webloc data")
                return nil
            }
            
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try data.write(to: fileURL)
                return fileURL
            } catch {
                Log.shelf.error("Error: \(error)")
                return nil
            }
        }
    }
    
    private func createFile(at url: URL, data: Data) -> URL? {
        do {
            try data.write(to: url)
            return url
        } catch {
            Log.shelf.error("❌ Failed to create temp file at \(url.path): \(error)")
            return nil
        }
    }
    func createZip(from urls: [URL], suggestedName: String? = nil) async -> URL? {
        let uuid = UUID().uuidString
        let workingDir = baseDirectory.appendingPathComponent("zip_\(uuid)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: workingDir, withIntermediateDirectories: true)
        } catch {
            Log.shelf.error("❌ Failed to create zip working directory: \(error)")
            return nil
        }

        // Helper to run zip process
        func runZip(arguments: [String], currentDirectory: URL) -> Bool {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            proc.arguments = arguments
            proc.currentDirectoryURL = currentDirectory
            do {
                try proc.run()
                proc.waitUntilExit()
                return proc.terminationStatus == 0
            } catch {
                Log.shelf.error("❌ Failed to run zip: \(error)")
                return false
            }
        }

        // Single-item optimization: do not copy contents into the working dir.
        if urls.count == 1, let src = urls.first {
            let isDir = (try? src.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let baseName = src.lastPathComponent
            let archiveName: String
            if isDir {
                // Folder: name as FolderName.zip and include the folder itself in the archive
                archiveName = "\(baseName).zip"
                let archiveURL = workingDir.appendingPathComponent(archiveName)
                // Run zip from the parent directory so the folder is stored as top-level entry
                let parent = src.deletingLastPathComponent()
                let args = ["-r", "-q", archiveURL.path, baseName]
                let ok = runZip(arguments: args, currentDirectory: parent)
                if ok {
                    return archiveURL
                } else {
                    return nil
                }
            } else {
                // File: include the file only (no parent folders). Name should include original extension.
                archiveName = "\(baseName).zip"
                let archiveURL = workingDir.appendingPathComponent(archiveName)
                let parent = src.deletingLastPathComponent()
                // -j to junk paths and store only the file
                let args = ["-j", "-q", archiveURL.path, baseName]
                let ok = runZip(arguments: args, currentDirectory: parent)
                if ok {
                    return archiveURL
                } else {
                    return nil
                }
            }
        }

        // Multi-item: copy items into working dir (so their relative structure is preserved), zip, then remove copies.
        for src in urls {
            let dest = workingDir.appendingPathComponent(src.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    // Avoid collision by appending a suffix
                    let unique = "\(UUID().uuidString)_\(src.lastPathComponent)"
                    try FileManager.default.copyItem(at: src, to: workingDir.appendingPathComponent(unique))
                } else {
                    try FileManager.default.copyItem(at: src, to: dest)
                }
            } catch {
                Log.shelf.error("⚠️ Failed to copy \(src.path) to working dir: \(error)")
            }
        }

        let archiveName = suggestedName ?? "Archive.zip"
        let archiveURL = workingDir.appendingPathComponent(archiveName)
        let args = ["-r", "-q", archiveURL.path, "."]
        let ok = runZip(arguments: args, currentDirectory: workingDir)
        if ok {
            // Remove the copied (uncompressed) items so the temp folder contains only the archive
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: workingDir, includingPropertiesForKeys: nil)
                for file in contents {
                    if file.standardizedFileURL != archiveURL.standardizedFileURL {
                        try FileManager.default.removeItem(at: file)
                    }
                }
            } catch {
                Log.shelf.error("⚠️ Failed to cleanup working directory after zip: \(error)")
            }
            return archiveURL
        } else {
            return nil
        }
    }
    
    // MARK: - Content Creation Helpers

    private func makeUniqueDirectory() -> URL {
        baseDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func safeFilename(_ suggestedName: String?, fallback: String) -> String {
        for candidate in [suggestedName, fallback] {
            guard let candidate else { continue }
            let name = URL(fileURLWithPath: candidate).lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, name != ".", name != ".." {
                return name
            }
        }
        return "Untitled"
    }
    
    
    private func createWeblocContent(for url: URL) -> String {
        return """
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
}
