//
//  ShortcutConstants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleSneakPeek = Self("toggleSneakPeek", initial: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", initial: .init(.i, modifiers: [.command, .shift]))
    /// Dropover's "New shelf" shortcut is Option-Shift-Space.
    static let showFloatingShelf = Self("showFloatingShelf", initial: .init(.space, modifiers: [.option, .shift]))
}
