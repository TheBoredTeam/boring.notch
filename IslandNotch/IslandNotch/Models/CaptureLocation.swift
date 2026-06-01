//  CaptureLocation.swift
//  IslandNotch
//
//  Purpose: Resolves where screenshots are saved. Desktop is convenient but may
//           be iCloud-synced; Application Support avoids that.
//  Layer: Model

import Foundation

/// Where the shots folder lives on disk.
enum CaptureLocation: String, Codable, CaseIterable, Identifiable {
    /// ~/Desktop/island-shots — convenient, but syncs if iCloud Desktop is on.
    case desktopIslandShots
    /// ~/Library/Application Support/<bundleid>/shots — never iCloud-synced.
    case appSupport

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .desktopIslandShots: return "Desktop (island-shots)"
        case .appSupport: return "Application Support"
        }
    }

    var subtitle: String {
        switch self {
        case .desktopIslandShots: return "~/Desktop/island-shots — easy to find, but syncs with iCloud Desktop."
        case .appSupport: return "~/Library/Application Support — out of the way, never iCloud-synced."
        }
    }

    /// Resolved folder URL, creating intermediate components lazily at use time.
    func resolvedFolderURL(bundleID: String) -> URL {
        let fm = FileManager.default
        switch self {
        case .desktopIslandShots:
            let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            return desktop.appendingPathComponent("island-shots", isDirectory: true)
        case .appSupport:
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fm.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support")
            return appSupport
                .appendingPathComponent(bundleID, isDirectory: true)
                .appendingPathComponent("shots", isDirectory: true)
        }
    }
}
