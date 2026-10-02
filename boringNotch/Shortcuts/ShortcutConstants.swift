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

    // Tab shortcuts are only registered while the notch is open (see TabShortcutController)
    static let selectTab1 = Self("selectTab1", initial: .init(.one, modifiers: [.command]))
    static let selectTab2 = Self("selectTab2", initial: .init(.two, modifiers: [.command]))
    static let nextTab = Self("nextTab", initial: .init(.tab, modifiers: [.control]))
    static let previousTab = Self("previousTab", initial: .init(.tab, modifiers: [.control, .shift]))

    static let tabShortcuts: [Self] = [.selectTab1, .selectTab2, .nextTab, .previousTab]
}

/// The notch never becomes key, so tab shortcuts have to be global hotkeys.
/// A registered hotkey swallows the keystroke even if its handler does nothing,
/// so they're only registered while at least one notch is open — otherwise ⌘1
/// etc. would be stolen from every other app.
@MainActor
enum TabShortcutController {
    private static var openViewModels = Set<ObjectIdentifier>()

    static func setOpen(_ isOpen: Bool, for viewModel: BoringViewModel) {
        let id = ObjectIdentifier(viewModel)
        if isOpen {
            openViewModels.insert(id)
        } else {
            openViewModels.remove(id)
        }
        updateRegistration()
    }

    /// Called when notch windows are torn down, so a view model that was open
    /// when its window went away can't keep the shortcuts registered.
    static func reset() {
        openViewModels.removeAll()
        updateRegistration()
    }

    static func updateRegistration() {
        if openViewModels.isEmpty {
            KeyboardShortcuts.disable(KeyboardShortcuts.Name.tabShortcuts)
        } else {
            KeyboardShortcuts.enable(KeyboardShortcuts.Name.tabShortcuts)
        }
    }
}
