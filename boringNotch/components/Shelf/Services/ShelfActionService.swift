//
//  ShelfActionService.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-07.
//

import AppKit
import Foundation

/// A service providing common actions for `ShelfItem`s, such as opening, revealing, or copying paths.
@MainActor
enum ShelfActionService {

    static func open(_ item: ShelfItem) {
        switch item.kind {
        case .file(let bookmarkData):
            Bookmark(data: bookmarkData).withAccess { url in
                NSWorkspace.shared.open(url)
            }
        case .link(let url):
            NSWorkspace.shared.open(url)
        case .text(let string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
    }

    static func reveal(_ item: ShelfItem) {
        guard case .file(let bookmarkData) = item.kind else { return }
        Bookmark(data: bookmarkData).withAccess { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func copyPath(_ item: ShelfItem) {
        guard case .file(let bookmarkData) = item.kind else { return }
        Bookmark(data: bookmarkData).withAccess { url in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
    }

    static func remove(_ item: ShelfItem) {
        ShelfStateViewModel.shared.remove(item)
    }
}

enum MarkItDownConversionError: LocalizedError {
    case unsupportedFormat(String)
    case helperMissing
    case temporaryFileCreationFailed
    case helperFailed(String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let fileExtension):
            return "The .\(fileExtension) format is not supported by the local converter."
        case .helperMissing:
            return "The bundled local MarkItDown converter could not be found."
        case .temporaryFileCreationFailed:
            return "Boring Notch could not create a temporary Markdown file."
        case .helperFailed(let message):
            return message.isEmpty ? "The local MarkItDown converter failed." : message
        case .outputMissing:
            return "The converter finished without creating a Markdown file."
        }
    }
}

/// Runs the bundled MarkItDown helper with local files only. Remote URLs, plugins,
/// cloud services, audio transcription, and network-backed OCR are intentionally excluded.
actor MarkItDownConversionService {
    static let shared = MarkItDownConversionService()

    private static let supportedExtensions: Set<String> = [
        "pdf", "docx", "pptx", "xlsx", "xls", "html", "htm",
        "csv", "json", "jsonl", "xml", "rss", "atom", "epub",
        "msg", "zip", "txt", "md", "markdown", "rst", "log"
    ]

    nonisolated static func supports(_ url: URL) -> Bool {
        url.isFileURL && supportedExtensions.contains(url.pathExtension.lowercased())
    }

    func convert(_ inputURL: URL) async throws -> URL {
        let fileExtension = inputURL.pathExtension.lowercased()
        guard Self.supports(inputURL) else {
            throw MarkItDownConversionError.unsupportedFormat(fileExtension)
        }

        guard let runtimeURL = Bundle.main.url(forResource: "markitdown-runtime", withExtension: nil) else {
            throw MarkItDownConversionError.helperMissing
        }
        let helperURL = runtimeURL.appendingPathComponent("markitdown-local", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw MarkItDownConversionError.helperMissing
        }

        guard let outputURL = await TemporaryFileStorageService.shared.createTempFile(
            for: .data(Data(), suggestedName: "\(inputURL.deletingPathExtension().lastPathComponent).md")
        ) else {
            throw MarkItDownConversionError.temporaryFileCreationFailed
        }

        let inputDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("markitdown-input-\(UUID().uuidString)", isDirectory: true)
        let localInputURL = inputDirectory.appendingPathComponent(inputURL.lastPathComponent)

        do {
            try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
            try inputURL.accessSecurityScopedResource { accessibleURL in
                try FileManager.default.copyItem(at: accessibleURL, to: localInputURL)
            }

            try await runHelper(helperURL, input: localInputURL, output: outputURL)

            guard FileManager.default.fileExists(atPath: outputURL.path),
                  (try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
                throw MarkItDownConversionError.outputMissing
            }

            try? FileManager.default.removeItem(at: inputDirectory)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: inputDirectory)
            TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: outputURL)
            throw error
        }
    }

    private func runHelper(_ helperURL: URL, input: URL, output: URL) async throws {
        let process = Process()
        let standardError = Pipe()

        process.executableURL = helperURL
        process.arguments = ["--input", input.path, "--output", output.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = standardError

        var environment = ProcessInfo.processInfo.environment
        environment["MARKITDOWN_LOCAL_ONLY"] = "1"
        environment["PYTHONNOUSERSITE"] = "1"
        environment["NO_PROXY"] = "*"
        environment["no_proxy"] = "*"
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
            environment.removeValue(forKey: key)
        }
        process.environment = environment

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finishedProcess in
                let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if finishedProcess.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: MarkItDownConversionError.helperFailed(errorText)
                    )
                }
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
