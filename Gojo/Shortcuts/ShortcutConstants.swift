//
//  Constants.swift
//  Gojo
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let clipboardHistoryPanel = Self("clipboardHistoryPanel", default: .init(.c, modifiers: [.shift, .command]))
    static let toggleMicrophone = Self("toggleMicrophone", default: .init(.f5, modifiers: [.function]))
    static let decreaseBacklight = Self("decreaseBacklight", default: .init(.f1, modifiers: [.command]))
    static let increaseBacklight = Self("increaseBacklight", default: .init(.f2, modifiers: [.command]))
    static let toggleSneakPeek = Self("toggleSneakPeek", default: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", default: .init(.i, modifiers: [.command, .shift]))
    static let windowLeftHalf = Self("windowLeftHalf", default: .init(.leftArrow, modifiers: [.control, .option]))
    static let windowRightHalf = Self("windowRightHalf", default: .init(.rightArrow, modifiers: [.control, .option]))
    static let windowTopHalf = Self("windowTopHalf", default: .init(.upArrow, modifiers: [.control, .option]))
    static let windowBottomHalf = Self("windowBottomHalf", default: .init(.downArrow, modifiers: [.control, .option]))
    static let windowMaximize = Self("windowMaximize", default: .init(.return, modifiers: [.control, .option]))
    static let windowZoom = Self("windowZoom", default: .init(.z, modifiers: [.control, .option]))
}
