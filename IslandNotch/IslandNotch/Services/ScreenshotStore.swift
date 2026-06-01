//  ScreenshotStore.swift
//  IslandNotch
//
//  Purpose: Observable root state for the shots folder — the app's whole
//           "database". Owns the entry list, resolves the folder, and exposes a
//           single capture/import entry point. Persistence + capture + import +
//           retention live in Service+Feature extensions.
//  Layer: Service

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ScreenshotStore {
    /// Newest-first list of screenshots shown in the notch shelf.
    private(set) var entries: [ScreenshotEntry] = []

    /// Same-file helper so extensions in other files can publish list updates.
    func setPublishedEntries(_ newEntries: [ScreenshotEntry]) {
        entries = newEntries.sorted { $0.ts > $1.ts }
    }

    /// Transient UI signal: the entry just copied to the clipboard (for a flash).
    var lastCopiedFileID: String?

    @ObservationIgnored let preferences: AppPreferences
    @ObservationIgnored let captureService: CaptureService
    @ObservationIgnored let bundleID: String
    /// Serializes all index.json reads/writes (see ScreenshotStore+Index).
    @ObservationIgnored let indexIO = IndexIO()

    init(preferences: AppPreferences,
         captureService: CaptureService = ScreencaptureCLIService(),
         bundleID: String = Bundle.main.bundleIdentifier ?? "com.constellagent.islandnotch") {
        self.preferences = preferences
        self.captureService = captureService
        self.bundleID = bundleID
    }

    // MARK: Folder resolution

    /// Current shots folder, derived from the user's capture-location preference.
    var folderURL: URL {
        preferences.captureLocation.resolvedFolderURL(bundleID: bundleID)
    }

    var indexURL: URL {
        folderURL.appendingPathComponent("index.json")
    }

    /// Ensures the shots folder exists. Safe to call repeatedly.
    @discardableResult
    func ensureFolder() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: folderURL, withIntermediateDirectories: true
            )
            return true
        } catch {
            Log.store.error("ensureFolder failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Lifecycle

    /// One-time startup: ensure folder, load + reconcile index, run retention.
    func bootstrap() async {
        ensureFolder()
        await reload()
        await runRetentionSweep()
    }

    // MARK: Filenames

    /// Filesystem-safe ISO8601 timestamp filename, e.g. "2026-05-30T14-03-22Z.png".
    func makeTimestampFilename(ext: String = "png") -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return "\(stamp).\(ext)"
    }
}
