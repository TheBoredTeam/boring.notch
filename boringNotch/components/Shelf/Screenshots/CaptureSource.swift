//
//  CaptureSource.swift
//  boringNotch
//
//  Purpose: Identifies how a screenshot entered the shelf. Drives the
//           per-source auto-copy policy (e.g. double-⌘ auto-copies, drag does not).
//  Layer: Model
//

import Foundation
import Defaults

/// Where a screenshot came from. Persisted on the shelf item and used to decide
/// whether the pasteable payload should be auto-copied to the clipboard.
enum CaptureSource: String, Codable, CaseIterable, Hashable, Identifiable, Defaults.Serializable {
    /// Double-tap ⌘ global gesture (CGEventTap).
    case doubleCommand
    /// Configurable global keyboard chord (KeyboardShortcuts).
    case chord
    /// Triggered from the menu-bar menu.
    case menu
    /// User dragged/threw an image file onto the notch shelf.
    case drop

    var id: String { rawValue }

    /// Human-readable label for Settings UI.
    var displayName: String {
        switch self {
        case .doubleCommand: return "Double-⌘ gesture"
        case .chord: return "Keyboard shortcut"
        case .menu: return "Menu-bar capture"
        case .drop: return "Drag & drop"
        }
    }
}
