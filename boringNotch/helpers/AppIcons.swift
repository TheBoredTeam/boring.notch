//
//  AppIcons.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 16/08/24.
//

import AppKit
import SwiftUI

/// Loads application icons away from the main thread and keeps them for the
/// lifetime of the process. Menu-bar settings can contain many rows, so doing
/// the NSWorkspace lookup from a row's `body` is particularly expensive.
final class AppIconCache: @unchecked Sendable {
    static let shared = AppIconCache()

    private let loadingQueue = DispatchQueue(
        label: "theboringteam.boringnotch.app-icon-cache",
        qos: .utility
    )
    private var imagesByBundleIdentifier: [String: NSImage] = [:]
    private var missingBundleIdentifiers = Set<String>()

    private init() {}

    func icons(for bundleIdentifiers: [String]) async -> [String: NSImage] {
        let identifiers = Array(Set(bundleIdentifiers)).sorted()
        guard !identifiers.isEmpty else { return [:] }

        return await withCheckedContinuation { continuation in
            loadingQueue.async { [self] in
                let workspace = NSWorkspace.shared
                var result: [String: NSImage] = [:]

                for identifier in identifiers {
                    if let cachedImage = imagesByBundleIdentifier[identifier] {
                        result[identifier] = cachedImage
                        continue
                    }
                    guard !missingBundleIdentifiers.contains(identifier),
                          let applicationURL = workspace.urlForApplication(
                              withBundleIdentifier: identifier
                          ) else {
                        missingBundleIdentifiers.insert(identifier)
                        continue
                    }

                    let image = workspace.icon(forFile: applicationURL.path)
                    imagesByBundleIdentifier[identifier] = image
                    result[identifier] = image
                }

                continuation.resume(returning: result)
            }
        }
    }
}

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

func AppIcon(for bundleID: String) -> Image {
    let workspace = NSWorkspace.shared
    
    if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
        let appIcon = workspace.icon(forFile: appURL.path)
        return Image(nsImage: appIcon)
    }
    
    return Image(nsImage: workspace.icon(for: .applicationBundle))
}


func AppIconAsNSImage(for bundleID: String) -> NSImage? {
    let workspace = NSWorkspace.shared
    
    if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
        let appIcon = workspace.icon(forFile: appURL.path)
        appIcon.size = NSSize(width: 256, height: 256)
        return appIcon
    }
    return nil
}
