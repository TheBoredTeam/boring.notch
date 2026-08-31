//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

struct MenuBarItemDescriptor: Codable, Sendable, Identifiable {
    let id: String
    let processIdentifier: Int32
    let bundleIdentifier: String?
    let applicationName: String
    let accessibilityIdentifier: String?
    let title: String?
    let displayName: String
    let frameX: Double
    let frameY: Double
    let frameWidth: Double
    let frameHeight: Double
}

struct MenuBarItemsResponse: Codable, Sendable {
    let items: [MenuBarItemDescriptor]
    let accessibilityAuthorized: Bool
    let errorMessage: String?
}

struct MenuBarActionResponse: Codable, Sendable {
    let success: Bool
    let errorMessage: String?
}

struct MenuBarMenuEntry: Codable, Sendable, Identifiable {
    let id: String
    let path: [Int]
    let title: String
    let isEnabled: Bool
    let isSeparator: Bool
    let isMarked: Bool
    let keyEquivalent: String?
    let keyEquivalentModifiers: UInt32
    let children: [MenuBarMenuEntry]
}

struct MenuBarMenuResponse: Codable, Sendable {
    let isSupported: Bool
    let originalMenuPresented: Bool
    let entries: [MenuBarMenuEntry]
    let errorMessage: String?
}

struct MenuBarMenuActionRequest: Codable, Sendable {
    let item: MenuBarItemDescriptor
    let entry: MenuBarMenuEntry
}

enum MenuBarItemMovePlacement: String, Codable, Sendable {
    case leftOfTarget
    case rightOfTarget
}

struct MenuBarItemMoveRequest: Codable, Sendable {
    let item: MenuBarItemDescriptor?
    let sourceWindowID: UInt32
    let sourceProcessIdentifier: Int32
    let sourceFrameX: Double
    let sourceFrameY: Double
    let sourceFrameWidth: Double
    let sourceFrameHeight: Double
    let targetWindowID: UInt32
    let targetFrameX: Double
    let targetFrameY: Double
    let targetFrameWidth: Double
    let targetFrameHeight: Double
    let placement: MenuBarItemMovePlacement
}

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol BoringNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Menu bar item discovery and activation (performed outside the app sandbox)
    func listMenuBarItems(with reply: @escaping (Data) -> Void)
    func activateMenuBarItem(_ descriptorData: Data, with reply: @escaping (Data) -> Void)
    func inspectMenuBarItem(_ descriptorData: Data, with reply: @escaping (Data) -> Void)
    func activateMenuBarMenuEntry(_ requestData: Data, with reply: @escaping (Data) -> Void)
    func moveMenuBarItem(_ requestData: Data, with reply: @escaping (Data) -> Void)
}
