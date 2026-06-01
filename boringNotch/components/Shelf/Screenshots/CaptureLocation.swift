//
//  CaptureLocation.swift
//  boringNotch
//
//  Purpose: Resolves where screenshots are saved. Desktop is convenient but may
//           be iCloud-synced; Application Support avoids that.
//  Layer: Model
//

import Foundation
import Defaults

/// Where the shots folder lives on disk.
enum CaptureLocation: String, Codable, CaseIterable, Identifiable, Defaults.Serializable {
    /// ~/Desktop/boring-shots — convenient, but syncs if iCloud Desktop is on.
    case desktopBoringShots
    /// ~/Library/Application Support/<bundleid>/shots — never iCloud-synced.
    case appSupport

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .desktopBoringShots: return "Desktop (boring-shots)"
        case .appSupport: return "Application Support"
        }
    }

    var subtitle: String {
        switch self {
        case .desktopBoringShots: return "~/Desktop/boring-shots — easy to find, but syncs with iCloud Desktop."
        case .appSupport: return "~/Library/Application Support — out of the way, never iCloud-synced."
        }
    }

    /// Resolved folder URL, creating intermediate components lazily at use time.
    func resolvedFolderURL(bundleID: String = bundleIdentifier) -> URL {
        let fm = FileManager.default
        switch self {
        case .desktopBoringShots:
            let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            return desktop.appendingPathComponent("boring-shots", isDirectory: true)
        case .appSupport:
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fm.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support")
            return appSupport
                .appendingPathComponent(bundleID, isDirectory: true)
                .appendingPathComponent("shots", isDirectory: true)
        }
    }

    /// True if `url` lives inside any of the possible capture folders. Used to
    /// gate destructive PNG deletes so retention/remove can never delete an
    /// arbitrary file a screenshot item might point at.
    static func isWithinACaptureFolder(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL.path
        for location in CaptureLocation.allCases {
            let folder = location.resolvedFolderURL().standardizedFileURL.path
            if standardized.hasPrefix(folder + "/") {
                return true
            }
        }
        return false
    }
}
