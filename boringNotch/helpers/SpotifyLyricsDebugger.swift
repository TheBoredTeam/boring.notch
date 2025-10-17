//
//  SpotifyLyricsDebugger.swift
//  boringNotch
//
//  Created for lyrics extraction debugging
//

import Foundation
import ApplicationServices
import Cocoa

class SpotifyLyricsDebugger: ObservableObject {
    private var timer: Timer?
    private var lastLyricsHash: Int = 0
    
    // MARK: - Public Methods
    
    func startDebugging() {
        print("🎵 [SpotifyLyricsDebugger] Starting lyrics extraction debugging...")
        
        // Check accessibility permissions first
        if !checkAccessibilityPermissions() {
            print("❌ [SpotifyLyricsDebugger] Accessibility permissions required")
            requestAccessibilityPermissions()
            return
        }
        
        print("✅ [SpotifyLyricsDebugger] Accessibility permissions granted")
        
        // Start periodic extraction
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.debugLyricsExtraction()
        }
        
        print("🔄 [SpotifyLyricsDebugger] Started periodic extraction (1s interval)")
    }
    
    func stopDebugging() {
        timer?.invalidate()
        timer = nil
        print("🛑 [SpotifyLyricsDebugger] Stopped debugging")
    }
    
    // MARK: - Permission Handling
    
    private func checkAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    private func requestAccessibilityPermissions() {
        print("🔐 [SpotifyLyricsDebugger] Requesting accessibility permissions...")
        
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        
        if !trusted {
            print("📋 [SpotifyLyricsDebugger] Please grant accessibility permissions in System Settings > Privacy & Security > Accessibility")
        }
    }
    
    // MARK: - Main Extraction Logic
    
    private func debugLyricsExtraction() {
        let timestamp = getCurrentTimestamp()
        
        // Find Spotify application
        guard let spotifyApp = findSpotifyApplication() else {
            print("❌ [\(timestamp)] Spotify not found or not running")
            return
        }
        
        print("✅ [\(timestamp)] Spotify application found")
        
        // Get all windows
        guard let windows = getApplicationWindows(spotifyApp) else {
            print("❌ [\(timestamp)] Could not get Spotify windows")
            return
        }
        
        print("📱 [\(timestamp)] Found \(windows.count) Spotify window(s)")
        
        // Search for lyrics in each window
        var foundLyrics = false
        for (index, window) in windows.enumerated() {
            print("🔍 [\(timestamp)] Searching window \(index + 1) for lyrics...")
            
            if let lyrics = searchForLyrics(in: window, depth: 0) {
                foundLyrics = true
                let lyricsHash = lyrics.hashValue
                
                // Only print if lyrics changed
                if lyricsHash != lastLyricsHash {
                    print("🎤 [\(timestamp)] LYRICS FOUND:")
                    print("📝 [\(timestamp)] \(lyrics)")
                    print("---")
                    lastLyricsHash = lyricsHash
                }
                break
            }
        }
        
        if !foundLyrics {
            print("🔍 [\(timestamp)] No lyrics found in any window")
        }
    }
    
    // MARK: - Spotify Application Discovery
    
    private func findSpotifyApplication() -> AXUIElement? {
        let runningApps = NSWorkspace.shared.runningApplications
        
        guard let spotifyApp = runningApps.first(where: { $0.bundleIdentifier == "com.spotify.client" }) else {
            return nil
        }
        
        let pid = spotifyApp.processIdentifier
        return AXUIElementCreateApplication(pid)
    }
    
    private func getApplicationWindows(_ app: AXUIElement) -> [AXUIElement]? {
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }
        
        return windows
    }
    
    // MARK: - Lyrics Search Logic
    
    private func searchForLyrics(in element: AXUIElement, depth: Int) -> String? {
        // Prevent infinite recursion
        guard depth < 10 else { return nil }
        
        // Get element attributes
        let role = getElementAttribute(element, attribute: kAXRoleAttribute as CFString) as? String
        let value = getElementAttribute(element, attribute: kAXValueAttribute as CFString) as? String
        let title = getElementAttribute(element, attribute: kAXTitleAttribute as CFString) as? String
        let description = getElementAttribute(element, attribute: kAXDescriptionAttribute as CFString) as? String
        
        // Debug output for interesting elements
        if depth <= 3 {
            let indent = String(repeating: "  ", count: depth)
            if let role = role {
                print("🔍 \(indent)Role: \(role)")
                if let value = value, !value.isEmpty {
                    print("🔍 \(indent)Value: \(value)")
                }
                if let title = title, !title.isEmpty {
                    print("🔍 \(indent)Title: \(title)")
                }
                if let description = description, !description.isEmpty {
                    print("🔍 \(indent)Description: \(description)")
                }
            }
        }
        
        // Check if this element contains lyrics-like text
        if let lyricsText = extractPotentialLyrics(role: role, value: value, title: title, description: description) {
            return lyricsText
        }
        
        // Search child elements
        if let children = getElementChildren(element) {
            for child in children {
                if let lyrics = searchForLyrics(in: child, depth: depth + 1) {
                    return lyrics
                }
            }
        }
        
        return nil
    }
    
    private func extractPotentialLyrics(role: String?, value: String?, title: String?, description: String?) -> String? {
        // Look for text elements that might contain lyrics
        let candidateTexts = [value, title, description].compactMap { $0 }
        
        for text in candidateTexts {
            // Check if text looks like lyrics
            if isLyricsLikeText(text) {
                return text
            }
        }
        
        return nil
    }
    
    private func isLyricsLikeText(_ text: String) -> Bool {
        // Simple heuristics to identify lyrics
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Must be substantial text
        guard trimmed.count > 10 else { return false }
        
        // Exclude common UI elements
        let excludePatterns = [
            "spotify", "play", "pause", "skip", "volume", "search", "playlist",
            "library", "home", "browse", "radio", "settings", "premium"
        ]
        
        let lowercaseText = trimmed.lowercased()
        for pattern in excludePatterns {
            if lowercaseText.contains(pattern) && trimmed.count < 100 {
                return false
            }
        }
        
        // Look for lyrics-like characteristics
        let hasMultipleLines = text.contains("\n")
        let hasTypicalLength = trimmed.count > 20 && trimmed.count < 500
        let hasWordPattern = trimmed.range(of: "\\b\\w+\\s+\\w+\\b", options: .regularExpression) != nil
        
        return hasTypicalLength && (hasMultipleLines || hasWordPattern)
    }
    
    // MARK: - Accessibility Helpers
    
    private func getElementAttribute(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        return result == .success ? value : nil
    }
    
    private func getElementChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        
        guard result == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        
        return children
    }
    
    // MARK: - Utility
    
    private func getCurrentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}

// MARK: - Debug Usage Extension

extension SpotifyLyricsDebugger {
    static func startDebugSession() {
        let debugger = SpotifyLyricsDebugger()
        debugger.startDebugging()
        
        // Keep the debugger alive for testing
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            debugger.stopDebugging()
            print("🏁 [SpotifyLyricsDebugger] Debug session completed")
        }
    }
}