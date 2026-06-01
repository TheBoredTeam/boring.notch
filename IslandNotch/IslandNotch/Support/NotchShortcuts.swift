//  NotchShortcuts.swift
//  IslandNotch
//
//  Purpose: Declares the global keyboard shortcut names owned by the app.
//           KeyboardShortcuts persists the user's binding in UserDefaults.
//  Layer: Support

import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// The configurable global chord that triggers an interactive capture.
    /// Defaults to ⌘⇧7 to avoid clashing with the system ⌘⇧4/5 screenshot tools.
    static let captureScreenshot = Self(
        "captureScreenshot",
        default: .init(.seven, modifiers: [.command, .shift])
    )
}
