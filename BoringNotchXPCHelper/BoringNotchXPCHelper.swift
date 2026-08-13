//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import ApplicationServices
import IOKit
import CoreGraphics

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {

    private struct BluetoothBatteryPartPayload: Codable {
        let kind: String
        let percentage: Int
        let isCharging: Bool
    }

    private struct BluetoothBatteryDevicePayload: Codable {
        let name: String
        let category: String
        let parts: [BluetoothBatteryPartPayload]
    }

    private struct RawAccessoryBattery {
        let name: String
        let groupKey: String
        let category: String
        let part: BluetoothBatteryPartPayload
    }
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    @objc func bluetoothAccessoryBatteryData(with reply: @escaping (NSData?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let pmsetEntries = self.readAccessoryPowerSources()
            let hidEntries = self.readBluetoothHIDBatteries()
            let devices = self.groupBluetoothBatteries(pmsetEntries + hidEntries)
            guard let data = try? JSONEncoder().encode(devices) else {
                reply(nil)
                return
            }
            reply(data as NSData)
        }
    }

    private func readAccessoryPowerSources() -> [RawAccessoryBattery] {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "accps", "-xml"]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8)
            else {
                return []
            }
            return parseAccessoryPowerSourcePlists(output)
        } catch {
            return []
        }
    }

    private func parseAccessoryPowerSourcePlists(_ output: String) -> [RawAccessoryBattery] {
        let marker = "<?xml"
        return output.components(separatedBy: marker).compactMap { chunk in
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = (marker + chunk).data(using: .utf8),
                  let dictionary = try? PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                  ) as? [String: Any],
                  dictionary["Type"] as? String == "Accessory Source",
                  dictionary["Is Present"] as? Bool != false,
                  let name = dictionary["Name"] as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let percentage = normalizedPercentage(dictionary["Current Capacity"])
            else {
                return nil
            }

            let transport = (dictionary["Transport Type"] as? String ?? "").lowercased()
            guard transport.contains("bluetooth") else { return nil }

            let partName = dictionary["Part Identifier"] as? String ?? "Main"
            let groupIdentifier = dictionary["Group Identifier"] as? String
            let groupKey = groupIdentifier?.isEmpty == false
                ? "accessory:\(groupIdentifier!)"
                : "name:\(normalizedDeviceName(name).lowercased())"
            let category = inferredDeviceCategory(
                name: name,
                reportedCategory: dictionary["Accessory Category"] as? String
            )

            return RawAccessoryBattery(
                name: normalizedDeviceName(name),
                groupKey: groupKey,
                category: category,
                part: .init(
                    kind: normalizedPartKind(partName),
                    percentage: percentage,
                    isCharging: dictionary["Is Charging"] as? Bool ?? false
                )
            )
        }
    }

    private func readBluetoothHIDBatteries() -> [RawAccessoryBattery] {
        guard let matching = IOServiceMatching("AppleDeviceManagementHIDEventService") else {
            return []
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var results: [RawAccessoryBattery] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any],
                  dictionary["BluetoothDevice"] as? Bool == true,
                  let name = dictionary["Product"] as? String,
                  let percentage = normalizedPercentage(dictionary["BatteryPercent"])
            else {
                continue
            }

            let normalizedName = normalizedDeviceName(name)
            results.append(
                .init(
                    name: normalizedName,
                    groupKey: "hid:\(normalizedName.lowercased())",
                    category: inferredDeviceCategory(name: normalizedName, reportedCategory: nil),
                    part: .init(kind: "main", percentage: percentage, isCharging: false)
                )
            )
        }
        return results
    }

    private func groupBluetoothBatteries(_ entries: [RawAccessoryBattery]) -> [BluetoothBatteryDevicePayload] {
        let grouped = Dictionary(grouping: entries, by: \.groupKey)
        return grouped.values.compactMap { entries in
            guard let first = entries.first else { return nil }
            let preferredName = entries.first(where: { $0.part.kind != "case" })?.name ?? first.name
            let preferredCategory = entries.first(where: { $0.category != "other" })?.category ?? first.category

            var partsByKind: [String: BluetoothBatteryPartPayload] = [:]
            for entry in entries {
                partsByKind[entry.part.kind] = entry.part
            }
            if partsByKind["left"] != nil || partsByKind["right"] != nil {
                partsByKind.removeValue(forKey: "combined")
                partsByKind.removeValue(forKey: "main")
            }

            let order = ["left", "right", "case", "main", "combined"]
            let parts = partsByKind.values.sorted { lhs, rhs in
                (order.firstIndex(of: lhs.kind) ?? order.count)
                    < (order.firstIndex(of: rhs.kind) ?? order.count)
            }
            guard !parts.isEmpty else { return nil }
            return .init(name: preferredName, category: preferredCategory, parts: parts)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func normalizedPercentage(_ value: Any?) -> Int? {
        let percentage: Int
        switch value {
        case let value as Int:
            percentage = value
        case let value as NSNumber:
            percentage = value.intValue
        case let value as Double:
            percentage = value <= 1 ? Int((value * 100).rounded()) : Int(value.rounded())
        case let value as String:
            percentage = Int(value.replacingOccurrences(of: "%", with: "")) ?? -1
        default:
            return nil
        }
        guard (0 ... 100).contains(percentage) else { return nil }
        return percentage
    }

    private func normalizedPartKind(_ rawValue: String) -> String {
        let value = rawValue.lowercased()
        if value.contains("left") || value == "l" { return "left" }
        if value.contains("right") || value == "r" { return "right" }
        if value.contains("case") || value.contains("盒") { return "case" }
        if value.contains("combined") { return "combined" }
        return "main"
    }

    private func normalizedDeviceName(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["充电盒", " Charging Case", " charging case"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        return value.isEmpty ? "Bluetooth device" : value
    }

    private func inferredDeviceCategory(name: String, reportedCategory: String?) -> String {
        let value = "\(name) \(reportedCategory ?? "")".lowercased()
        if value.contains("airpods") || value.contains("headphone") || value.contains("headset")
            || value.contains("earbud") || value.contains("audio") || value.contains("耳机")
        {
            return "headphones"
        }
        if value.contains("keyboard") || value.contains("键盘") { return "keyboard" }
        if value.contains("trackpad") || value.contains("触控板") { return "trackpad" }
        if value.contains("mouse") || value.contains("鼠标") { return "mouse" }
        return "other"
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}
