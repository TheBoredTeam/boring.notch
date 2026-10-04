//
//  NotchKeyboardFocus.swift
//  boringNotch
//
//  Lets the notch panel accept typing only while a tab with text input is showing.
//

import AppKit

@MainActor
enum NotchKeyboardFocus {
    /// The notch panels are non-activating, so becoming key lets them receive keystrokes
    /// without bringing boringNotch to the front.
    static var allowsKeyFocus: Bool {
        BoringViewCoordinator.shared.currentView.acceptsTextInput
    }

    /// Hands keyboard focus back to the app the user was working in.
    static func relinquish() {
        guard let keyWindow = NSApp.keyWindow,
              keyWindow is BoringNotchSkyLightWindow || keyWindow is BoringNotchWindow
        else { return }

        keyWindow.makeFirstResponder(nil)
        keyWindow.resignKey()

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost != NSRunningApplication.current {
            frontmost.activate()
        }
    }
}
