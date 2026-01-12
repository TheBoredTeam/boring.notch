//
//  AppIconHelper.swift
//  boringNotch
//
//  Helper to fetch app icons from app names
//

import AppKit
import Foundation

/// Helper to fetch and cache app icons from application names
enum AppIconHelper {
    /// Cache for app icons to avoid repeated lookups
    private static var iconCache: [String: NSImage] = [:]
    
    /// Default clipboard icon when app icon is unavailable
    static var defaultIcon: NSImage {
        NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard") ?? NSImage()
    }
    
    /// Get the app icon for a given app name
    /// - Parameter appName: The localized name of the application (e.g., "Safari", "Xcode")
    /// - Returns: The app's icon or a default clipboard icon if not found
    static func icon(for appName: String?) -> NSImage {
        guard let appName = appName, !appName.isEmpty else {
            return defaultIcon
        }
        
        // Check cache first
        if let cached = iconCache[appName] {
            return cached
        }
        
        // Try to find the app by bundle identifier
        if let bundleID = bundleIdentifier(for: appName),
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            iconCache[appName] = icon
            return icon
        }
        
        // Try finding by app name in Applications folder
        let appPaths = [
            "/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app",
            NSHomeDirectory() + "/Applications/\(appName).app"
        ]
        
        for path in appPaths {
            if FileManager.default.fileExists(atPath: path) {
                let icon = NSWorkspace.shared.icon(forFile: path)
                iconCache[appName] = icon
                return icon
            }
        }
        
        // Try to find running application with this name
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }),
           let bundleURL = runningApp.bundleURL {
            let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
            iconCache[appName] = icon
            return icon
        }
        
        // Cache the default icon for this app name to avoid repeated lookups
        iconCache[appName] = defaultIcon
        return defaultIcon
    }
    
    /// Common bundle identifiers for well-known apps
    private static func bundleIdentifier(for appName: String) -> String? {
        let knownApps: [String: String] = [
            "Safari": "com.apple.Safari",
            "Finder": "com.apple.finder",
            "Xcode": "com.apple.dt.Xcode",
            "Terminal": "com.apple.Terminal",
            "Notes": "com.apple.Notes",
            "Messages": "com.apple.MobileSMS",
            "Mail": "com.apple.mail",
            "Calendar": "com.apple.iCal",
            "Reminders": "com.apple.reminders",
            "Preview": "com.apple.Preview",
            "TextEdit": "com.apple.TextEdit",
            "System Preferences": "com.apple.systempreferences",
            "System Settings": "com.apple.systempreferences",
            "App Store": "com.apple.AppStore",
            "Photos": "com.apple.Photos",
            "Music": "com.apple.Music",
            "Podcasts": "com.apple.podcasts",
            "TV": "com.apple.TV",
            "News": "com.apple.news",
            "Stocks": "com.apple.stocks",
            "Home": "com.apple.Home",
            "Voice Memos": "com.apple.VoiceMemos",
            "Contacts": "com.apple.AddressBook",
            "FaceTime": "com.apple.FaceTime",
            "Maps": "com.apple.Maps",
            "Books": "com.apple.iBooksX",
            "Keynote": "com.apple.iWork.Keynote",
            "Numbers": "com.apple.iWork.Numbers",
            "Pages": "com.apple.iWork.Pages",
            "GarageBand": "com.apple.garageband10",
            "iMovie": "com.apple.iMovieApp",
            "Final Cut Pro": "com.apple.FinalCut",
            "Logic Pro": "com.apple.logic10",
            "Slack": "com.tinyspeck.slackmacgap",
            "Discord": "com.hnc.Discord",
            "Figma": "com.figma.Desktop",
            "Notion": "notion.id",
            "Visual Studio Code": "com.microsoft.VSCode",
            "Chrome": "com.google.Chrome",
            "Google Chrome": "com.google.Chrome",
            "Firefox": "org.mozilla.firefox",
            "Arc": "company.thebrowser.Browser",
            "Telegram": "ru.keepcoder.Telegram",
            "WhatsApp": "net.whatsapp.WhatsApp",
            "Spotify": "com.spotify.client",
            "1Password": "com.1password.1password",
            "Bitwarden": "com.bitwarden.desktop",
            "iTerm": "com.googlecode.iterm2",
            "Warp": "dev.warp.Warp-Stable"
        ]
        
        return knownApps[appName]
    }
    
    /// Clear the icon cache
    static func clearCache() {
        iconCache.removeAll()
    }
}
