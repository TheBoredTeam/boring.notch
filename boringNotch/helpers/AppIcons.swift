//
//  AppIcons.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 16/08/24.
//

import SwiftUI
import AppKit

struct AppIcons {
    
    func getIcon(file path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path)
        else { return nil }
        
        return NSWorkspace.shared.icon(forFile: path)
    }
    
    func getIcon(bundleID: String) -> NSImage? {
        guard let path = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        )?.absoluteString
        else { return nil }
        
        return getIcon(file: path)
    }
    
        /// Easily read Info.plist as a Dictionary from any bundle by accessing .infoDictionary on Bundle
    func bundle(forBundleID: String) -> Bundle? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: forBundleID)
        else { return nil }
        
        return Bundle(url: url)
    }
    
}

func normalizeBundleIdentifier(_ bundleID: String) -> String {
    let lower = bundleID.lowercased()
    
    // Handle Safari Technology Preview rendering helper processes
    if lower.hasPrefix("com.apple.safaritechnologypreview.") {
        return "com.apple.SafariTechnologyPreview"
    }
    
    // Handle WebKit / Safari rendering helper processes
    if lower.hasPrefix("com.apple.webkit.") || lower.hasPrefix("com.apple.safari.") {
        return "com.apple.Safari"
    }
    
    // General rule for Chromium/Electron helper processes
    // e.g., "com.google.Chrome.helper" -> "com.google.Chrome"
    let components = bundleID.components(separatedBy: ".")
    if let helperIndex = components.firstIndex(where: { $0.lowercased() == "helper" }) {
        return components[0..<helperIndex].joined(separator: ".")
    }
    
    return bundleID
}

func appIcon(for bundleID: String) -> Image {
    let workspace = NSWorkspace.shared
    let normalizedID = normalizeBundleIdentifier(bundleID)
    
    if let appURL = workspace.urlForApplication(withBundleIdentifier: normalizedID) {
        let appIcon = workspace.icon(forFile: appURL.path)
        return Image(nsImage: appIcon)
    }
    
    return Image(nsImage: workspace.icon(for: .applicationBundle))
}


func appIconAsNSImage(for bundleID: String) -> NSImage? {
    let workspace = NSWorkspace.shared
    let normalizedID = normalizeBundleIdentifier(bundleID)
    
    if let appURL = workspace.urlForApplication(withBundleIdentifier: normalizedID) {
        let appIcon = workspace.icon(forFile: appURL.path)
        appIcon.size = NSSize(width: 256, height: 256)
        return appIcon
    }
    return nil
}

/// Resolves an app's bundle ID from its display name when the XPC helper's
/// own one-shot match came back empty (the notification then arrives with a
/// nil bundleID and every icon surface falls back to the grey bell).
/// Fallback chain, cheapest first:
///   1. running applications, matched on normalized `localizedName`
///   2. direct probe of the standard /Applications locations
///   3. one bounded listing of those directories (filename first, then
///      CFBundleDisplayName / CFBundleName)
/// Hits and misses are memoized, so a chatty app never re-scans the disk.
final class BundleIDResolver {
    static let shared = BundleIDResolver()

    /// Thread-safety: the only production caller (`SystemNotificationManager.add`)
    /// is @MainActor, but the lock costs nothing and keeps the cache sound if a
    /// caller ever resolves off-queue. It is only held around dictionary access,
    /// never during disk I/O — a duplicate concurrent lookup can do the scan
    /// twice, in which case the last (identical) write wins.
    private let lock = NSLock()
    private var cache: [String: String?] = [:]

    /// Probe order: /Applications, then the user's own ~/Applications, then
    /// /System/Applications. The app is sandboxed, so `homeDirectoryForCurrentUser`
    /// would point at the container — build the real home from the login name
    /// instead. Injectable so tests can point the resolver at a fixture dir.
    static let defaultSearchDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/Users/\(NSUserName())/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
    ]

    func bundleID(forAppNamed name: String, searchDirectories: [URL] = BundleIDResolver.defaultSearchDirectories) -> String? {
        let target = Self.normalizedAppName(name)
        guard !target.isEmpty else { return nil }

        lock.lock()
        let cached = cache[target]
        lock.unlock()
        if let cached { return cached }

        let resolved = resolve(target: target, name: name, searchDirectories: searchDirectories)

        lock.lock()
        cache[target] = resolved
        lock.unlock()
        return resolved
    }

    private func resolve(target: String, name: String, searchDirectories: [URL]) -> String? {
        // 1. Running apps — the same match the helper attempts, redone here in
        //    case the app (re)launched between posting and capture.
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            guard let localizedName = $0.localizedName else { return false }
            return Self.normalizedAppName(localizedName) == target
        })?.bundleIdentifier {
            return running
        }

        // 2. Direct probes: the name as reported, plus a space-stripped
        //    variant ("Google Chrome" -> "GoogleChrome.app" style installs).
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutSpaces = trimmed.replacingOccurrences(of: " ", with: "")
        let candidates = withoutSpaces == trimmed ? [trimmed] : [trimmed, withoutSpaces]
        for directory in searchDirectories {
            for candidate in candidates {
                let url = directory.appendingPathComponent(candidate).appendingPathExtension("app")
                if let bundleID = bundleIdentifier(at: url) { return bundleID }
            }
        }

        // 3. One bounded listing per directory — no recursion into subfolders.
        for directory in searchDirectories {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
            ) else { continue }
            for entry in entries where entry.pathExtension == "app" {
                guard let bundle = Bundle(url: entry), let bundleID = bundle.bundleIdentifier else { continue }
                if Self.normalizedAppName(entry.deletingPathExtension().lastPathComponent) == target {
                    return bundleID
                }
                let infoNames = [
                    bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                    bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                ]
                if infoNames.contains(where: { $0.map { Self.normalizedAppName($0) == target } ?? false }) {
                    return bundleID
                }
            }
        }
        return nil
    }

    /// Mirrors the helper's `normalizedAppName`: both sides can carry invisible
    /// bidi marks — WhatsApp's `localizedName` is literally "\u{200E}WhatsApp" —
    /// so strip them along with case and surrounding whitespace before comparing.
    static func normalizedAppName(_ name: String) -> String {
        name.filter { !$0.unicodeScalars.allSatisfy(bidiControlCharacters.contains) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func bundleIdentifier(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    /// Directional formatting characters Notification Center and app names both
    /// sprinkle in: LRM/RLM, the isolate family, and the embedding/override set.
    private static let bidiControlCharacters: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "\u{200E}\u{200F}")      // LRM, RLM
        set.insert(charactersIn: "\u{2066}"..."\u{2069}") // isolates + PDI
        set.insert(charactersIn: "\u{202A}"..."\u{202E}") // embeddings/overrides
        return set
    }()
}

