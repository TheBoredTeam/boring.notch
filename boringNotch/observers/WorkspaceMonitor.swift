import SwiftUI
import Combine
import CoreGraphics
import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let desktop1 = Self("desktop1")
    static let desktop2 = Self("desktop2")
    static let desktop3 = Self("desktop3")
    static let desktop4 = Self("desktop4")
    static let desktop5 = Self("desktop5")
    static let desktop6 = Self("desktop6")
    static let desktop7 = Self("desktop7")
    static let desktop8 = Self("desktop8")
    static let desktop9 = Self("desktop9")
}

// Private API declarations
private let CGSMainConnectionID: @convention(c) () -> UInt32 = {
    let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    let symbol = dlsym(handle, "CGSMainConnectionID")
    return unsafeBitCast(symbol, to: (@convention(c) () -> UInt32).self)
}()

private let CGSCopyManagedDisplaySpaces: @convention(c) (UInt32) -> Unmanaged<CFArray>? = {
    let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    let symbol = dlsym(handle, "CGSCopyManagedDisplaySpaces")
    return unsafeBitCast(symbol, to: (@convention(c) (UInt32) -> Unmanaged<CFArray>?).self)
}()

private let CGSGetWindowLevel: @convention(c) (UInt32, UInt32) -> UInt32 = {
    let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    let symbol = dlsym(handle, "CGSGetWindowLevel")
    return unsafeBitCast(symbol, to: (@convention(c) (UInt32, UInt32) -> UInt32).self)
}()

class WorkspaceMonitor: ObservableObject {
    @Published var currentStatus: String = ""
    @Published var shouldShowStatus: Bool = false
    private var workspaceObserver: NSObjectProtocol?
    private var hideTimer: Timer?
    private var currentDesktop: Int = 1
    
    init() {
        setupWorkspaceObserver()
        setupKeyboardShortcuts()
        updateStatus()
    }
    
    private func setupWorkspaceObserver() {
        // Observe when apps become active
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatus()
        }
    }
    
    private func setupKeyboardShortcuts() {
        // Set up shortcuts for desktops 1-9
        let desktopNames: [KeyboardShortcuts.Name] = [.desktop1, .desktop2, .desktop3, .desktop4, .desktop5, .desktop6, .desktop7, .desktop8, .desktop9]
        
        // Key codes for numbers 1-9 on the main keyboard (not numpad)
        let numberKeyCodes = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        
        for (index, name) in desktopNames.enumerated() {
            let desktopNumber = index + 1
            let keyCode = numberKeyCodes[index]
            let key = KeyboardShortcuts.Key(rawValue: keyCode)
            KeyboardShortcuts.setShortcut(.init(key, modifiers: [.control]), for: name)
            
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                self?.switchToDesktop(desktopNumber)
            }
        }
    }
    
    private func getActiveWindowTitle() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        
        // Request accessibility permissions if needed
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessEnabled {
            return nil
        }
        
        // Get the frontmost window using Accessibility API
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        
        if result == .success, let windowRef = value {
            let window = windowRef as! AXUIElement
            var title: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            
            if titleResult == .success, let windowTitle = title as? String {
                return windowTitle
            }
        }
        
        return nil
    }
    
    private func updateStatus() {
        // Cancel any existing hide timer
        hideTimer?.invalidate()
        
        // Get the frontmost application
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        
        // Get the app name
        let appName = app.localizedName ?? "App"
        
        // Get the window title if available
        if let windowTitle = getActiveWindowTitle() {
            // Format: "App: Title" (truncated if too long)
            let maxLength = 20
            if windowTitle.count > maxLength {
                currentStatus = "\(appName): \(windowTitle.prefix(maxLength))…"
            } else {
                currentStatus = "\(appName): \(windowTitle)"
            }
        } else {
            // Just show the app name if no window title
            currentStatus = appName
        }
        
        // Show the status
        shouldShowStatus = true
        
        // Set a timer to hide the status after 2 seconds
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.shouldShowStatus = false
        }
    }
    
    private func switchToDesktop(_ number: Int) {
        // Update current desktop
        currentDesktop = number
        
        // Show the status
        currentStatus = "Desktop \(number)"
        shouldShowStatus = true
        
        // Cancel any existing timer
        hideTimer?.invalidate()
        
        // Set a new timer to hide the status
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.shouldShowStatus = false
        }
        
        // Try to switch to the desktop using AppleScript
        let script = """
        tell application "System Events"
            -- First try clicking the desktop button in Mission Control
            try
                tell process "Dock"
                    click (every button whose value of attribute "AXDescription" is "desktop \(number)")
                end tell
            on error
                -- If that fails, try using keyboard shortcuts
                key code \(number + 17) using {control down}
            end try
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("Error switching desktop: \(error)")
                // If both methods fail, try one more time with a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let retryScript = NSAppleScript(source: """
                        tell application "System Events"
                            key code \(number + 17) using {control down}
                        end tell
                    """) {
                        retryScript.executeAndReturnError(nil)
                    }
                }
            }
        }
    }
    
    deinit {
        if let workspaceObserver = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        hideTimer?.invalidate()
    }
} 
