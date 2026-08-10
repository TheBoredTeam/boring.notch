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
    nonisolated func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    nonisolated func requestAccessibilityAuthorization()
    nonisolated func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    nonisolated func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    nonisolated func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    nonisolated func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    nonisolated func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    // returns the displayID that will be used for built-in brightness operations (main or internal fallback)
    nonisolated func displayIDForBrightness(with reply: @escaping (NSNumber?) -> Void)
    nonisolated func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    nonisolated func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    nonisolated func adjustScreenBrightness(by value: Float, with reply: @escaping (Bool) -> Void)
    // Lunar brightness events (performed by the helper)
    nonisolated func isLunarAvailable(with reply: @escaping (Bool) -> Void)
    nonisolated func startLunarEventStream(with reply: @escaping (Bool) -> Void)
    nonisolated func stopLunarEventStream()
    /// Write Lunar's hideOSD preference (disable/enable Lunar's OSD when we replace it).
    nonisolated func setLunarOSDHidden(_ hide: Bool, with reply: @escaping (Bool) -> Void)
}
