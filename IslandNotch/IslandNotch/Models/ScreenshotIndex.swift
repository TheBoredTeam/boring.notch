//  ScreenshotIndex.swift
//  IslandNotch
//
//  Purpose: The on-disk index.json document — a versioned list of entries.
//           The shots folder is the whole "database"; this file is a cache/log.
//  Layer: Model

import Foundation

/// Codable wrapper for index.json. Versioned so the schema can evolve.
struct ScreenshotIndex: Codable {
    static let currentVersion = 1

    var version: Int
    var entries: [ScreenshotEntry]

    init(version: Int = ScreenshotIndex.currentVersion, entries: [ScreenshotEntry] = []) {
        self.version = version
        self.entries = entries
    }

    /// JSON encoder/decoder configured with ISO8601 dates, matching the schema
    /// documented in the README (`ts` is an ISO8601 string).
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
