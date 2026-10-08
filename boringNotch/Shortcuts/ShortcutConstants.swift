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
    // No default binding, so it can't clash with anything; the user can record one in Settings > Shortcuts.
    static let togglePomodoro = Self("togglePomodoro")
}
