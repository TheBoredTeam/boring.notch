//  SystemSettingsLinks.swift
//  IslandNotch
//
//  Purpose: Deep links into the System Settings privacy panes so the user can
//           grant permissions in one click when we can't do it programmatically.
//  Layer: Support

import AppKit

enum SystemSettingsLinks {
    /// Privacy & Security → Accessibility (needed for the double-⌘ CGEventTap).
    static let accessibility = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    /// Privacy & Security → Screen Recording (needed to capture screen content).
    static let screenRecording = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    /// Opens a settings URL, ignoring failures (the pane simply won't appear).
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
