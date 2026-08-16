//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol BoringNotchXPCHelperLunarListener {
    func lunarEventDidUpdate(_ event: BNLunarBrightnessEvent)
    func lunarStreamDidStop(_ reason: String?)
}

@objc(BNLunarBrightnessEvent)
final class BNLunarBrightnessEvent: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let brightness: Double
    let display: Int

    init(brightness: Double, display: Int) {
        self.brightness = brightness
        self.display = display
        super.init()
    }

    required init?(coder: NSCoder) {
        brightness = coder.decodeDouble(forKey: "brightness")
        display = coder.decodeInteger(forKey: "display")
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(brightness, forKey: "brightness")
        coder.encode(display, forKey: "display")
    }
}

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
    // returns the displayID that will be used for built-in brightness operations (main or internal fallback)
    func displayIDForBrightness(with reply: @escaping (NSNumber?) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    func adjustScreenBrightness(by value: Float, with reply: @escaping (Bool) -> Void)
    // Lunar brightness events (performed by the helper)
    func isLunarAvailable(with reply: @escaping (Bool) -> Void)
    func startLunarEventStream(with reply: @escaping (Bool) -> Void)
    func stopLunarEventStream()
    /// Write Lunar's hideOSD preference (disable/enable Lunar's OSD when we replace it).
    func setLunarOSDHidden(_ hide: Bool, with reply: @escaping (Bool) -> Void)
    // Notification Center banner observation (performed by the helper)
    func startNotificationWatching(with reply: @escaping (Bool) -> Void)
    func stopNotificationWatching()
    func replyToNotification(_ token: String, text: String, with reply: @escaping (Bool) -> Void)
    func sendIMessage(_ text: String, toChatNamed name: String, with reply: @escaping (Bool) -> Void)
    func performNotificationAction(_ token: String, name: String, with reply: @escaping (Bool) -> Void)
    func openNotification(_ token: String, with reply: @escaping (Bool) -> Void)
    func dismissNotification(_ token: String, with reply: @escaping (Bool) -> Void)
    func holdNotification(_ token: String)
    func releaseNotification(_ token: String)
    func notificationDebugDump(with reply: @escaping (String) -> Void)
}

/// Pushed from the helper back to the app. The app sets an object conforming to
/// this as its connection's `exportedObject`.
@objc protocol BoringNotchXPCHelperDelegate {
    /// Keys: token, appName, bundleID, title, subtitle, body, actions
    /// (`actions` is newline-joined).
    func notificationDidAppear(_ payload: [String: String])
    func notificationDidDisappear(_ token: String)
}

/// A connection has exactly one exported object, and the helper calls back for
/// both Lunar events and notification banners — so the app vends a single
/// object conforming to both.
@objc protocol BoringNotchXPCAppDelegate: BoringNotchXPCHelperLunarListener, BoringNotchXPCHelperDelegate {}
