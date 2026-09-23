//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

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
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    // Probes read/write capability with a same-value write; call only when control is enabled.
    func displayIDForBrightness(with reply: @escaping (NSNumber?) -> Void)
    func currentScreenBrightness(
        forDisplayID displayID: NSNumber, with reply: @escaping (NSNumber?, NSNumber?) -> Void)
    func setScreenBrightness(
        _ value: Float, forDisplayID displayID: NSNumber,
        with reply: @escaping (NSNumber?, NSNumber?) -> Void)
    /// Replies the display ID and authoritative resulting brightness.
    func adjustScreenBrightness(
        by value: Float, forDisplayID displayID: NSNumber,
        with reply: @escaping (NSNumber?, NSNumber?) -> Void)
    // Lunar brightness events (performed by the helper)
    func isLunarAvailable(with reply: @escaping (Bool) -> Void)
    func startLunarEventStream(with reply: @escaping (Bool) -> Void)
    func stopLunarEventStream()
    func setLunarOSDHidden(_ hide: Bool, with reply: @escaping (Bool) -> Void)
    func startNotificationWatching(with reply: @escaping (Bool) -> Void)
    func stopNotificationWatching()
    func setNotificationFilter(_ bundleIDs: [String], allApps: Bool)
}

@objc protocol BoringNotchXPCHelperDelegate {
    func notificationDidAppear(_ payload: [String: String])
}

@objc protocol BoringNotchXPCAppDelegate: BoringNotchXPCHelperLunarListener, BoringNotchXPCHelperDelegate {}
