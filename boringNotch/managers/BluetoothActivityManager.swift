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

/// Reads Bluetooth-device battery levels from the IORegistry.
enum BluetoothBatteryReader {
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

            if let combined = intProperty(service, "BatteryPercentCombined"), combined > 0 {
                result = combined
            } else if let single = intProperty(service, "BatteryPercent"), single > 0 {
                result = single
            } else {
                let left = intProperty(service, "BatteryPercentLeft") ?? 0
                let right = intProperty(service, "BatteryPercentRight") ?? 0
                let values = [left, right].filter { $0 > 0 }
                if !values.isEmpty { result = values.reduce(0, +) / values.count }
            }
            if result != nil { break }
        }
        return result
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
