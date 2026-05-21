//
//  GojoXPCHelperProtocol.swift
//  GojoXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol GojoXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    func focusedWindowSnapshot(_ promptIfNeeded: Bool, with reply: @escaping (NSDictionary) -> Void)
    func setFocusedWindowFrame(_ normalFrame: NSDictionary, windowID: NSNumber?, with reply: @escaping (Bool) -> Void)
    func setWindowFrame(_ normalFrame: NSDictionary, pid: NSNumber, windowID: NSNumber?, with reply: @escaping (Bool) -> Void)
    func raiseWindow(_ pid: NSNumber, windowID: NSNumber?, with reply: @escaping (Bool) -> Void)
    func enumerateWindows(forScreen screenUUID: NSString?, with reply: @escaping (NSArray) -> Void)
    func performZoom(_ pid: NSNumber, windowID: NSNumber?, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
}
