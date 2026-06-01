//  ScreenshotEntry.swift
//  IslandNotch
//
//  Purpose: One row in index.json — a single captured/imported screenshot.
//  Layer: Model

import Foundation

/// A single screenshot record. `file` is stored RELATIVE to the shots folder so
/// the folder stays self-contained and portable if the user moves it.
struct ScreenshotEntry: Codable, Identifiable, Hashable {
    /// File name relative to the shots folder, e.g. "2026-05-30T14-03-22Z.png".
    var file: String
    /// Optional note typed alongside the shot (reserved for a future feature).
    var prompt: String?
    /// Capture timestamp (ISO8601 on disk).
    var ts: Date
    /// How this shot was captured. Optional for forward/back compatibility with
    /// older index files that predate the field.
    var source: CaptureSource?

    /// Stable identity for SwiftUI lists — the relative file name is unique.
    var id: String { file }

    init(file: String, prompt: String? = nil, ts: Date = Date(), source: CaptureSource? = nil) {
        self.file = file
        self.prompt = prompt
        self.ts = ts
        self.source = source
    }

    /// Absolute URL of this entry's PNG, resolved against the store's folder.
    func url(in folder: URL) -> URL {
        folder.appendingPathComponent(file)
    }
}
