//
//  BluetoothBatteryManager.swift
//  boringNotch
//
//  Created by boringNotch contributors on 2026-04-19.
//

import Combine
import Defaults
import Foundation
import IOBluetooth

struct BluetoothDeviceInfo: Identifiable, Equatable {
    let id: String  // MAC address or UUID
    let name: String
    let batteryLevel: Int  // 0-100, -1 if unknown
    let deviceType: BluetoothDeviceType
    let isConnected: Bool
    let lastUpdated: Date

    var batteryIcon: String {
        if batteryLevel < 0 { return "battery.0" }
        if batteryLevel <= 10 { return "battery.0" }
        if batteryLevel <= 25 { return "battery.25" }
        if batteryLevel <= 50 { return "battery.50" }
        if batteryLevel <= 75 { return "battery.75" }
        return "battery.100"
    }
}

enum BluetoothDeviceType: String {
    case headphones
    case earbuds
    case speaker
    case keyboard
    case mouse
    case trackpad
    case gamepad
    case unknown

    var icon: String {
        switch self {
        case .headphones: return "headphones"
        case .earbuds: return "earbuds"
        case .speaker: return "hifispeaker"
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .gamepad: return "gamecontroller"
        case .unknown: return "wave.3.right"
        }
    }
}

/// Monitors connected Bluetooth devices for battery levels
class BluetoothBatteryManager: NSObject, ObservableObject {
    static let shared = BluetoothBatteryManager()

    @Published var devices: [BluetoothDeviceInfo] = []

    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 30
    private var settingsCancellable: AnyCancellable?

    // Cache of IORegistry battery data keyed by device address or product name
    private var ioRegistryBatteryCache: [String: Int] = [:]

    private override init() {
        super.init()

        // Auto-start/stop when setting changes
        settingsCancellable = Defaults.publisher(.showBluetoothBattery)
            .sink { [weak self] change in
                if change.newValue {
                    self?.startMonitoring()
                } else {
                    self?.stopMonitoring()
                }
            }

        if Defaults[.showBluetoothBattery] {
            startMonitoring()
        }
    }

    func startMonitoring() {
        refreshDevices()
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) {
            [weak self] _ in
            self?.refreshDevices()
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refreshDevices() {
        // First, scan IORegistry for all battery-reporting Bluetooth devices
        scanIORegistryForBatteries()

        var discovered: [BluetoothDeviceInfo] = []

        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            DispatchQueue.main.async { self.devices = [] }
            return
        }

        for device in pairedDevices {
            guard device.isConnected() else { continue }

            let name = device.name ?? "Unknown Device"
            let address = device.addressString ?? UUID().uuidString
            let deviceType = classifyDevice(device)

            // Try multiple methods to get battery
            let batteryLevel = getBatteryLevel(deviceName: name, address: address)

            let info = BluetoothDeviceInfo(
                id: address,
                name: name,
                batteryLevel: batteryLevel,
                deviceType: deviceType,
                isConnected: true,
                lastUpdated: Date()
            )
            discovered.append(info)
        }

        DispatchQueue.main.async {
            self.devices = discovered
        }
    }

    /// Scans the entire IORegistry for services that report BatteryPercent
    /// and caches them by product name for later matching
    private func scanIORegistryForBatteries() {
        ioRegistryBatteryCache.removeAll()

        // Method 1: Check AppleDeviceManagementHIDEventService (covers most HID devices)
        scanServiceClass("AppleDeviceManagementHIDEventService")

        // Method 2: Check IOBluetoothHIDDriver (covers BT keyboards, mice)
        scanServiceClass("IOBluetoothHIDDriver")

        // Method 3: Check AppleHSBluetoothDevice (covers AirPods, Beats, some BT audio)
        scanServiceClass("AppleHSBluetoothDevice")

        // Method 4: Broad scan — any IOService with BatteryPercent
        scanServiceClass("IOHIDDevice")
    }

    private func scanServiceClass(_ className: String) {
        let matchingDict = IOServiceMatching(className)
        var iterator: io_iterator_t = 0

        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard kr == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            // Look for BatteryPercent
            if let batteryPercent = IORegistryEntryCreateCFProperty(
                service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? Int, batteryPercent >= 0 && batteryPercent <= 100 {

                // Try to identify by Product name
                if let product = IORegistryEntryCreateCFProperty(
                    service, "Product" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? String {
                    ioRegistryBatteryCache[product.lowercased()] = batteryPercent
                }

                // Also try by device name
                if let deviceName = IORegistryEntryCreateCFProperty(
                    service, "DeviceName" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? String {
                    ioRegistryBatteryCache[deviceName.lowercased()] = batteryPercent
                }

                // Also try by serial number / address
                if let serial = IORegistryEntryCreateCFProperty(
                    service, "SerialNumber" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? String {
                    ioRegistryBatteryCache[serial.lowercased()] = batteryPercent
                }
            }

            // Some devices use "BatteryLevel" instead
            if let batteryLevel = IORegistryEntryCreateCFProperty(
                service, "BatteryLevel" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? Int, batteryLevel >= 0 && batteryLevel <= 100 {
                if let product = IORegistryEntryCreateCFProperty(
                    service, "Product" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? String {
                    ioRegistryBatteryCache[product.lowercased()] = batteryLevel
                }
            }
        }
    }

    /// Attempts to get battery level for a device using cached IORegistry data
    private func getBatteryLevel(deviceName: String, address: String) -> Int {
        let nameLower = deviceName.lowercased()

        // Direct name match
        if let level = ioRegistryBatteryCache[nameLower] {
            return level
        }

        // Partial name match (e.g. "OnePlus Buds 3" matching "oneplus buds 3")
        for (key, level) in ioRegistryBatteryCache {
            if key.contains(nameLower) || nameLower.contains(key) {
                return level
            }
        }

        // Address match
        if let level = ioRegistryBatteryCache[address.lowercased()] {
            return level
        }

        // Fallback: try system_profiler (slow but comprehensive)
        return getBatteryFromSystemProfiler(deviceName: deviceName)
    }

    /// Last resort: parse system_profiler for battery info
    private func getBatteryFromSystemProfiler(deviceName: String) -> Int {
        let task = Process()
        task.launchPath = "/usr/sbin/system_profiler"
        task.arguments = ["SPBluetoothDataType", "-json"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let btData = json["SPBluetoothDataType"] as? [[String: Any]]
            {
                for controller in btData {
                    // Check connected devices
                    if let connectedDevices = controller["device_connected"] as? [[String: Any]] {
                        for deviceDict in connectedDevices {
                            for (key, value) in deviceDict {
                                guard let deviceInfo = value as? [String: Any] else { continue }
                                let name = key
                                if name.lowercased().contains(deviceName.lowercased())
                                    || deviceName.lowercased().contains(name.lowercased())
                                {
                                    // Look for battery level in device info
                                    if let batteryStr = deviceInfo["device_batteryLevelMain"] as? String,
                                       let level = Int(batteryStr.replacingOccurrences(of: "%", with: ""))
                                    {
                                        return level
                                    }
                                    if let batteryStr = deviceInfo["device_batteryLevel"] as? String,
                                       let level = Int(batteryStr.replacingOccurrences(of: "%", with: ""))
                                    {
                                        return level
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            // system_profiler failed, return unknown
        }

        return -1
    }

    /// Classifies a Bluetooth device based on its device class and name
    private func classifyDevice(_ device: IOBluetoothDevice) -> BluetoothDeviceType {
        let name = (device.name ?? "").lowercased()

        if name.contains("bud") || name.contains("earbud") || name.contains("pods") {
            return .earbuds
        }
        if name.contains("headphone") || name.contains("over-ear") || name.contains("wh-") {
            return .headphones
        }
        if name.contains("speaker") || name.contains("soundbar") || name.contains("jbl")
            || name.contains("ue boom")
        {
            return .speaker
        }
        if name.contains("keyboard") || name.contains("keychron") { return .keyboard }
        if name.contains("mouse") || name.contains("magic mouse") { return .mouse }
        if name.contains("trackpad") { return .trackpad }
        if name.contains("controller") || name.contains("gamepad") || name.contains("dualsense") {
            return .gamepad
        }

        // Fallback to device class
        let majorClass = device.deviceClassMajor
        switch majorClass {
        case 0x05:  // Peripheral (HID)
            let minorClass = device.deviceClassMinor
            if minorClass == 0x01 { return .keyboard }
            if minorClass == 0x02 { return .mouse }
            return .unknown
        case 0x04:  // Audio/Video
            return .headphones
        default:
            return .unknown
        }
    }

    deinit {
        stopMonitoring()
    }
}
