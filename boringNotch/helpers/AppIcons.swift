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
        resolvedAppIcon(for: bundleID)
    }

    /// Easily read Info.plist as a Dictionary from any bundle by accessing .infoDictionary on Bundle
    func bundle(forBundleID: String) -> Bundle? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: forBundleID)
        else { return nil }

        return Bundle(url: url)
    }

}

func AppIcon(for bundleID: String) -> Image {
    if let appIcon = resolvedAppIcon(for: bundleID) {
        return Image(nsImage: appIcon)
    }

    return Image(nsImage: NSWorkspace.shared.icon(for: .applicationBundle))
}


func AppIconAsNSImage(for bundleID: String) -> NSImage? {
    if let appIcon = resolvedAppIcon(for: bundleID) {
        appIcon.size = NSSize(width: 256, height: 256)
        return appIcon
    }
    return nil
}

private func resolvedAppIcon(for bundleID: String?) -> NSImage? {
    guard let bundleID, !bundleID.isEmpty else { return nil }

    for candidateURL in candidateApplicationURLs(for: bundleID) {
        guard let appBundleURL = outermostAppBundleURL(from: candidateURL) else { continue }
        guard FileManager.default.fileExists(atPath: appBundleURL.path) else { continue }

        return NSWorkspace.shared.icon(forFile: appBundleURL.path)
    }

    return nil
}

private func candidateApplicationURLs(for bundleID: String) -> [URL] {
    let workspace = NSWorkspace.shared
    var candidates: [URL] = []
    var seenPaths = Set<String>()

    func append(_ url: URL?) {
        guard let url else { return }
        let path = url.standardizedFileURL.path
        guard !path.isEmpty, seenPaths.insert(path).inserted else { return }
        candidates.append(url)
    }

    append(workspace.urlForApplication(withBundleIdentifier: bundleID))

    for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
        append(application.bundleURL)
        append(application.executableURL)
    }

    return candidates
}

private func outermostAppBundleURL(from url: URL) -> URL? {
    var currentURL = url.standardizedFileURL
    var resolvedURL: URL?

    while currentURL.path != "/" && !currentURL.path.isEmpty {
        if currentURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            resolvedURL = currentURL
        }

        let parentURL = currentURL.deletingLastPathComponent()
        if parentURL.path == currentURL.path {
            break
        }
        currentURL = parentURL
    }

    return resolvedURL
}
