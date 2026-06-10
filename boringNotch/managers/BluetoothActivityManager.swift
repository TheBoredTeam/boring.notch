//
//  BluetoothActivityManager.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-09.
//
//  Detects Bluetooth device connections (AirPods, mice, keyboards, headphones)
//  and surfaces an iOS-style popup with battery level on the notch.
//
//  Connection detection uses IOBluetooth. Battery level is read directly from
//  the IORegistry (IOKit, in-process, sandbox-permitted) — no subprocess needed.
//

import Combine
import Defaults
import Foundation
import IOBluetooth
import IOKit

struct BluetoothDeviceInfo: Equatable {
    enum Kind {
        case airpods, airpodsPro, airpodsMax, headphones, mouse, keyboard, generic
    }

    let name: String
    let address: String
    var batteryPercent: Int?
    let kind: Kind

    var iconName: String {
        switch kind {
        case .airpods: return "airpods"
        case .airpodsPro: return "airpodspro"
        case .airpodsMax: return "airpodsmax"
        case .headphones: return "headphones"
        case .mouse: return "magicmouse"
        case .keyboard: return "keyboard"
        case .generic: return "antenna.radiowaves.left.and.right"
        }
    }

    static func kind(forName name: String) -> Kind {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return .airpodsMax }
        if lower.contains("airpods pro") { return .airpodsPro }
        if lower.contains("airpods") { return .airpods }
        if lower.contains("headphone") || lower.contains("buds") || lower.contains("beats") {
            return .headphones
        }
        if lower.contains("mouse") || lower.contains("trackpad") { return .mouse }
        if lower.contains("keyboard") { return .keyboard }
        return .generic
    }
}

final class BluetoothActivityManager: NSObject, ObservableObject {
    static let shared = BluetoothActivityManager()

    @Published private(set) var lastConnectedDevice: BluetoothDeviceInfo?

    private var connectNotification: IOBluetoothUserNotification?
    private let coordinator = BoringViewCoordinator.shared
    /// Suppresses repeat popups for the same device (BT devices reconnect often
    /// for power saving, which otherwise spams the notch).
    private var lastShown: [String: Date] = [:]
    private let cooldown: TimeInterval = 90

    private override init() { super.init() }

    /// Registers for device-connection notifications.
    func start() {
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
    }

    @objc private func deviceConnected(
        _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
    ) {
        // Track disconnect so we can ignore stale popups if needed.
        device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
        guard Defaults[.enableBluetoothPopup] else { return }
        present(device: device)
    }

    @objc private func deviceDisconnected(
        _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
    ) {
        notification.unregister()
    }

    private func present(device: IOBluetoothDevice) {
        // Skip nameless/generic devices (background reconnects show up as an
        // unnamed "Bluetooth Device" and are just noise).
        guard let name = device.name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        let address = device.addressString ?? ""

        // Suppress repeats of the same device within the cooldown window.
        if let last = lastShown[address], Date().timeIntervalSince(last) < cooldown {
            return
        }
        lastShown[address] = Date()

        var info = BluetoothDeviceInfo(
            name: name,
            address: address,
            batteryPercent: BluetoothBatteryReader.batteryPercent(forAddress: address),
            kind: BluetoothDeviceInfo.kind(forName: name)
        )

        publish(info)

        // IORegistry battery values often populate a moment after connection;
        // re-read a couple of times to fill it in.
        for delay in [1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.lastConnectedDevice?.address == address else { return }
                if let battery = BluetoothBatteryReader.batteryPercent(forAddress: address) {
                    info.batteryPercent = battery
                    self.lastConnectedDevice = info
                }
            }
        }
    }

    private func publish(_ info: BluetoothDeviceInfo) {
        DispatchQueue.main.async {
            self.lastConnectedDevice = info
            self.coordinator.toggleExpandingView(status: true, type: .bluetooth)
        }
    }
}

/// A connected device with a readable battery level (for the Widgets-tab panel).
struct DeviceBattery: Identifiable, Equatable {
    let name: String
    let address: String
    let percent: Int

    var id: String { address.isEmpty ? name : address }
    var iconName: String {
        BluetoothDeviceInfo(name: name, address: address, batteryPercent: percent,
                            kind: BluetoothDeviceInfo.kind(forName: name)).iconName
    }
}

/// Reads Bluetooth-device battery levels.
enum BluetoothBatteryReader {
    /// Fast, in-process IORegistry read — used for the connection popup.
    /// Works for devices Apple exposes via AppleDeviceManagementHIDEventService;
    /// returns nil for devices that only report battery over the Bluetooth daemon
    /// (e.g. some AirPods), in which case the popup just shows a checkmark.
    static func batteryPercent(forAddress address: String) -> Int? {
        let target = normalize(address)
        guard !target.isEmpty else { return nil }

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        var result: Int?
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let addr = property(service, "DeviceAddress") as? String,
                normalize(addr) == target
            else { continue }
            result = batteryPercent(of: service)
            if result != nil { break }
        }
        return result
    }

    /// All connected devices with a battery level, read from
    /// `system_profiler SPBluetoothDataType` (the same source the macOS
    /// Bluetooth menu uses — covers AirPods/headphones that the IORegistry
    /// doesn't expose). Runs a subprocess, so call this off the main thread.
    static func allDevices() -> [DeviceBattery] {
        guard let json = runSystemProfiler(),
            let root = json["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        var devices: [DeviceBattery] = []
        for controller in root {
            guard let connected = controller["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let info = value as? [String: Any],
                        let percent = batteryPercent(from: info)
                    else { continue }
                    let address = (info["device_address"] as? String) ?? ""
                    devices.append(
                        DeviceBattery(name: name.trimmingCharacters(in: .whitespaces),
                                      address: address, percent: percent))
                }
            }
        }
        return devices.sorted { $0.name < $1.name }
    }

    private static func runSystemProfiler() -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPBluetoothDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    /// Battery from a system_profiler device dict. Values look like "94%".
    /// For earbuds reports the lower of left/right (the limiting cell).
    private static func batteryPercent(from info: [String: Any]) -> Int? {
        func percent(_ key: String) -> Int? {
            guard let raw = info[key] as? String else { return nil }
            return Int(raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        }
        if let single = percent("device_batteryLevel") { return single }
        let buds = [percent("device_batteryLevelLeft"), percent("device_batteryLevelRight")]
            .compactMap { $0 }
        if let lowest = buds.min() { return lowest }
        return percent("device_batteryLevelCase")
    }

    private static func batteryPercent(of service: io_registry_entry_t) -> Int? {
        if let combined = intProperty(service, "BatteryPercentCombined"), combined > 0 {
            return combined
        }
        if let single = intProperty(service, "BatteryPercent"), single > 0 {
            return single
        }
        let left = intProperty(service, "BatteryPercentLeft") ?? 0
        let right = intProperty(service, "BatteryPercentRight") ?? 0
        let values = [left, right].filter { $0 > 0 }
        return values.isEmpty ? nil : values.reduce(0, +) / values.count
    }

    private static func intProperty(_ service: io_registry_entry_t, _ key: String) -> Int? {
        (property(service, key) as? NSNumber)?.intValue
    }

    private static func property(_ service: io_registry_entry_t, _ key: String) -> Any? {
        guard let cf = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        ) else { return nil }
        return cf.takeRetainedValue()
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
