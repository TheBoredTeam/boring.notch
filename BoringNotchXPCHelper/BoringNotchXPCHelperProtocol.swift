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

/// AirPods battery information transferred via XPC.
/// Uses -1 to indicate unavailable values since NSNumber? doesn't work well with XPC.
@objc(BNAirPodsBatteryInfo)
final class BNAirPodsBatteryInfo: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    
    /// Battery level of the left earpiece (0-100), -1 if unavailable
    @objc let left: Int
    /// Battery level of the right earpiece (0-100), -1 if unavailable
    @objc let right: Int
    /// Battery level of the charging case (0-100), -1 if unavailable
    @objc let caseLevel: Int
    
    @objc init(left: Int, right: Int, caseLevel: Int) {
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
        super.init()
    }
    
    required init?(coder: NSCoder) {
        left = coder.decodeInteger(forKey: "left")
        right = coder.decodeInteger(forKey: "right")
        caseLevel = coder.decodeInteger(forKey: "caseLevel")
        super.init()
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(left, forKey: "left")
        coder.encode(right, forKey: "right")
        coder.encode(caseLevel, forKey: "caseLevel")
    }
    
    /// Returns true if any battery info is available (value >= 0)
    @objc var hasDetailedInfo: Bool {
        left >= 0 || right >= 0 || caseLevel >= 0
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
    // AirPods battery info (requires running outside sandbox to access system_profiler)
    func getAirPodsBatteryInfo(with reply: @escaping (BNAirPodsBatteryInfo?) -> Void)
}

/*
 To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

     connectionToService = NSXPCConnection(serviceName: "theboringteam.boringnotch.BoringNotchXPCHelper")
     connectionToService.remoteObjectInterface = NSXPCInterface(with: (any BoringNotchXPCHelperProtocol).self)
     connectionToService.resume()

 Once you have a connection to the service, you can use it like this:

     if let proxy = connectionToService.remoteObjectProxy as? BoringNotchXPCHelperProtocol {
         proxy.performCalculation(firstNumber: 23, secondNumber: 19) { result in
             NSLog("Result of calculation is: \(result)")
         }
     }

 And, when you are finished with the service, clean up the connection like this:

     connectionToService.invalidate()
*/
