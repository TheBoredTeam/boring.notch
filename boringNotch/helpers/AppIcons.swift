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

func AppIcon(for bundleID: String) -> Image {
    let workspace = NSWorkspace.shared
    let normalizedID = normalizeBundleIdentifier(bundleID)
    
    if let appURL = workspace.urlForApplication(withBundleIdentifier: normalizedID) {
        let appIcon = workspace.icon(forFile: appURL.path)
        return Image(nsImage: appIcon)
    }
    
    return Image(nsImage: workspace.icon(for: .applicationBundle))
}


func AppIconAsNSImage(for bundleID: String) -> NSImage? {
    let workspace = NSWorkspace.shared
    let normalizedID = normalizeBundleIdentifier(bundleID)
    
    if let appURL = workspace.urlForApplication(withBundleIdentifier: normalizedID) {
        let appIcon = workspace.icon(forFile: appURL.path)
        appIcon.size = NSSize(width: 256, height: 256)
        return appIcon
    }
    return nil
}

