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

func AppIcon(forFilePath path: String) -> Image {
    let workspace = NSWorkspace.shared
    let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path

    if FileManager.default.fileExists(atPath: standardizedPath) {
        let appIcon = workspace.icon(forFile: standardizedPath)
        return Image(nsImage: appIcon)
    }

    return Image(nsImage: workspace.icon(for: .applicationBundle))
}

func AppIconAsNSImage(forFilePath path: String) -> NSImage? {
    let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
    guard FileManager.default.fileExists(atPath: standardizedPath) else { return nil }

    let appIcon = NSWorkspace.shared.icon(forFile: standardizedPath)
    appIcon.size = NSSize(width: 256, height: 256)
    return appIcon
}

func AppIcon(for item: QuickLaunchAppItem) -> Image {
    if !item.appPath.isEmpty {
        return AppIcon(forFilePath: item.appPath)
    }

    if !item.bundleIdentifier.isEmpty {
        return AppIcon(for: item.bundleIdentifier)
    }

    return Image(nsImage: NSWorkspace.shared.icon(for: .applicationBundle))
}
