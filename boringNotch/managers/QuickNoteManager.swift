//
//  QuickNoteManager.swift
//  boringNotch
//
//  Captures quick notes straight into an Obsidian vault. Notes are appended as
//  timestamped bullets to a per-day Markdown file inside a configurable folder
//  (defaults to the vault's raw/inbox entry point). The app is non-sandboxed,
//  so writes go directly through FileManager.
//

import Foundation
import Combine
import Defaults
import AppKit

struct QuickNoteEntry: Identifiable, Equatable {
    let id = UUID()
    let time: String   // "HH:mm"
    let text: String
}

@MainActor
final class QuickNoteManager: ObservableObject {
    static let shared = QuickNoteManager()

    @Published private(set) var todaysEntries: [QuickNoteEntry] = []
    @Published private(set) var lastError: String?
    @Published private(set) var savedFlash = false

    private init() {
        reloadToday()
    }

    // MARK: - Paths

    private var folderURL: URL {
        URL(fileURLWithPath: (Defaults[.quickNoteFolder] as NSString).expandingTildeInPath, isDirectory: true)
    }

    private static func dayStamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func timeStamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    var todaysFileURL: URL {
        let prefix = Defaults[.quickNoteFilePrefix]
        return folderURL.appendingPathComponent("\(prefix)-\(Self.dayStamp()).md")
    }

    /// Human-readable destination for display in the UI.
    var destinationLabel: String {
        let path = todaysFileURL.path
        return (path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Capture

    @discardableResult
    func save(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let url = todaysFileURL
            // Collapse internal newlines so one capture stays one bullet.
            let oneLine = text.replacingOccurrences(of: "\n", with: " · ")
            let bullet = "- \(Self.timeStamp()) — \(oneLine)\n"

            if fm.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                if let data = bullet.data(using: .utf8) { handle.write(data) }
            } else {
                let header = """
                ---
                type: capture
                date: \(Self.dayStamp())
                ---

                # Captures — \(Self.dayStamp())

                \(bullet)
                """
                try header.write(to: url, atomically: true, encoding: .utf8)
            }

            lastError = nil
            flashSaved()
            reloadToday()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Read back

    func reloadToday() {
        let url = todaysFileURL
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            todaysEntries = []
            return
        }
        var entries: [QuickNoteEntry] = []
        for line in content.components(separatedBy: .newlines) {
            // Match "- HH:mm — text"
            guard line.hasPrefix("- ") else { continue }
            let body = line.dropFirst(2)
            guard let dashRange = body.range(of: " — ") else { continue }
            let time = String(body[body.startIndex..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let text = String(body[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard time.count == 5, time.contains(":") else { continue }
            entries.append(QuickNoteEntry(time: time, text: text))
        }
        todaysEntries = entries.reversed() // newest first
    }

    func revealInFinder() {
        let url = todaysFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([folderURL])
        }
    }

    private func flashSaved() {
        savedFlash = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            savedFlash = false
        }
    }
}
