//
//  LyricsDebugTest.swift
//  boringNotch
//
//  Created for simple lyrics debugging test
//

import Foundation
import ApplicationServices

class LyricsDebugTest {
    static func testAccessibility() {
        print("🔍 [LyricsDebugTest] Testing accessibility access...")
        
        // Check if accessibility is enabled
        let trusted = AXIsProcessTrusted()
        print("✅ [LyricsDebugTest] Accessibility trusted: \(trusted)")
        
        if !trusted {
            print("🔐 [LyricsDebugTest] Requesting accessibility permissions...")
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
            let _ = AXIsProcessTrustedWithOptions(options)
            return
        }
        
        // Try to find Spotify
        let runningApps = NSWorkspace.shared.runningApplications
        guard let spotifyApp = runningApps.first(where: { $0.bundleIdentifier == "com.spotify.client" }) else {
            print("❌ [LyricsDebugTest] Spotify not found. Please open Spotify and try again.")
            return
        }
        
        print("✅ [LyricsDebugTest] Found Spotify (PID: \(spotifyApp.processIdentifier))")
        
        // Create accessibility element for Spotify
        let pid = spotifyApp.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        
        // Try to get windows
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
        
        if result == .success, let windows = windowsRef as? [AXUIElement] {
            print("✅ [LyricsDebugTest] Found \(windows.count) Spotify windows")
            
            // Print basic info about first window
            if let firstWindow = windows.first {
                var titleRef: CFTypeRef?
                let titleResult = AXUIElementCopyAttributeValue(firstWindow, kAXTitleAttribute as CFString, &titleRef)
                
                if titleResult == .success, let title = titleRef as? String {
                    print("📱 [LyricsDebugTest] First window title: '\(title)'")
                } else {
                    print("📱 [LyricsDebugTest] Could not get window title")
                }
            }
        } else {
            print("❌ [LyricsDebugTest] Could not access Spotify windows (result: \(result))")
        }
    }
}