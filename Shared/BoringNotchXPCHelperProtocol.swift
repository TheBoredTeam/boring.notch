//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

struct BNSystemMetricSelection: OptionSet, Sendable {
    let rawValue: Int

    static let cpu = BNSystemMetricSelection(rawValue: 1 << 0)
    static let gpu = BNSystemMetricSelection(rawValue: 1 << 1)
    static let memory = BNSystemMetricSelection(rawValue: 1 << 2)
    static let cpuTemperature = BNSystemMetricSelection(rawValue: 1 << 3)
    static let cpuProcesses = BNSystemMetricSelection(rawValue: 1 << 4)
    static let gpuProcesses = BNSystemMetricSelection(rawValue: 1 << 5)
    static let memoryProcesses = BNSystemMetricSelection(rawValue: 1 << 6)
}

struct BNProcessMetricPayload: Codable, Sendable {
    let pid: Int32
    let name: String
    let executablePath: String?
    let cpuUsagePercent: Double?
    let gpuTimeNanoseconds: UInt64?
    let memoryBytes: UInt64?
}

struct BNSystemMetricPayload: Codable, Sendable {
    let cpuUserTicks: UInt32
    let cpuSystemTicks: UInt32
    let cpuIdleTicks: UInt32
    let cpuNiceTicks: UInt32
    let gpuUsagePercent: Double?
    let memoryUsedBytes: UInt64
    let memoryTotalBytes: UInt64
    let cpuTemperatureCelsius: Double?
    let thermalState: Int
    let sampleUptimeNanoseconds: UInt64
    let processes: [BNProcessMetricPayload]
}

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
    func systemMetrics(_ requestedMetrics: Int, with reply: @escaping (Data) -> Void)
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    func displayIDForBrightness(with reply: @escaping (NSNumber?) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    func adjustScreenBrightness(by value: Float, with reply: @escaping (NSNumber?) -> Void)
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
