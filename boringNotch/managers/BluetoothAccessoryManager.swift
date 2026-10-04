//
//  BluetoothAccessoryManager.swift
//  boringNotch
//
//  Announces Bluetooth accessories (AirPods, headphones, keyboards, mice…)
//  connecting or disconnecting, along with their battery level when available.
//

import Combine
import Defaults
import Foundation
import IOBluetooth
import IOKit

struct AccessoryBattery: Equatable {
    var single: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    var isEmpty: Bool { single == nil && left == nil && right == nil }

    /// The level that best represents the accessory: the lowest earbud for AirPods-style devices.
    var primary: Int? {
        if let left, let right { return min(left, right) }
        return single ?? left ?? right
    }
}

struct AccessoryEvent: Equatable {
    let address: String
    var name: String
    var icon: String
    var isConnected: Bool
    var battery: AccessoryBattery
}

@MainActor
final class BluetoothAccessoryManager: NSObject, ObservableObject {
    static let shared = BluetoothAccessoryManager()

    @Published private(set) var lastEvent: AccessoryEvent?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var refreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    /// IOBluetooth reports already-connected devices right after registering; those are not new connections.
    private var ignoreConnectionsUntil = Date.distantPast

    private override init() {
        super.init()
        Defaults.publisher(.showBluetoothAccessories)
            .sink { [weak self] change in
                Task { @MainActor in
                    change.newValue ? self?.start() : self?.stop()
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard connectNotification == nil else { return }
        ignoreConnectionsUntil = Date().addingTimeInterval(2)
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        refreshTask?.cancel()
        lastEvent = nil
    }

    // MARK: - IOBluetooth callbacks

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }

        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )

        guard Date() >= ignoreConnectionsUntil else { return }
        announce(device, connected: true)

        // Battery levels are often published a moment after the link comes up.
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            for delay in [1.0, 2.5] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled,
                      var event = self.lastEvent, event.address == address, event.isConnected else { return }
                let battery = Self.battery(for: device)
                guard battery != event.battery else { continue }
                event.battery = battery
                self.lastEvent = event
                BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .bluetooth)
            }
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        if let address = device.addressString {
            disconnectNotifications[address] = nil
        }
        announce(device, connected: false)
    }

    private func announce(_ device: IOBluetoothDevice, connected: Bool) {
        guard Defaults[.showBluetoothAccessories], let address = device.addressString else { return }
        lastEvent = AccessoryEvent(
            address: address,
            name: device.name ?? String(localized: "Bluetooth device"),
            icon: Self.icon(for: device),
            isConnected: connected,
            battery: connected ? Self.battery(for: device) : AccessoryBattery()
        )
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .bluetooth)
    }

    // MARK: - Device details

    private static func icon(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }

        switch device.deviceClassMajor {
        case UInt32(kBluetoothDeviceClassMajorAudio):
            return device.deviceClassMinor == UInt32(kBluetoothDeviceClassMinorAudioLoudspeaker)
                ? "hifispeaker.fill" : "headphones"
        case UInt32(kBluetoothDeviceClassMajorPeripheral):
            if name.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
            if name.contains("mouse") { return "magicmouse.fill" }
            if name.contains("controller") { return "gamecontroller.fill" }
            return "keyboard.fill"
        case UInt32(kBluetoothDeviceClassMajorPhone):
            return "iphone"
        default:
            return "dot.radiowaves.left.and.right"
        }
    }

    /// Reads battery levels exposed by IOBluetooth (AirPods, Beats, most headsets) and falls back
    /// to the HID registry used by Magic Keyboard, Mouse and Trackpad.
    static func battery(for device: IOBluetoothDevice) -> AccessoryBattery {
        func level(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)),
                  let value = (device.value(forKey: key) as? NSNumber)?.intValue,
                  (1...100).contains(value) else { return nil }
            return value
        }

        var battery = AccessoryBattery(
            single: level("batteryPercentSingle"),
            left: level("batteryPercentLeft"),
            right: level("batteryPercentRight"),
            caseLevel: level("batteryPercentCase")
        )
        if battery.isEmpty, let address = device.addressString {
            battery.single = hidBatteryLevel(address: address)
        }
        return battery
    }

    private static func hidBatteryLevel(address: String) -> Int? {
        let normalized = { (value: String) in value.lowercased().filter(\.isHexDigit) }
        let target = normalized(address)

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleDeviceManagementHIDEventService"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let deviceAddress = IORegistryEntryCreateCFProperty(service, "DeviceAddress" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String,
                  normalized(deviceAddress) == target,
                  let percent = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Int
            else { continue }
            return percent
        }
        return nil
    }
}
