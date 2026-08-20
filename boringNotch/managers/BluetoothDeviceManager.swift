//
//  BluetoothDeviceManager.swift
//  boringNotch
//
//  Created by Claude on 2026-07-05.
//

import Combine
import Defaults
import Foundation
import IOBluetooth
import IOKit

struct BluetoothDeviceEvent: Equatable {
    var name: String
    var iconName: String
    var batteryPercent: Int?
    var leftPercent: Int?
    var rightPercent: Int?
    var casePercent: Int?

    var hasBatteryInfo: Bool {
        batteryPercent != nil || leftPercent != nil || rightPercent != nil
    }
}

/// Watches classic Bluetooth device connections (IOBluetooth, public API) and
/// reads battery levels from the IOKit HID registry. The `BatteryPercent*`
/// registry keys are undocumented but stable across recent macOS versions;
/// every read degrades gracefully to an icon-only activity.
@MainActor
final class BluetoothDeviceManager: NSObject, ObservableObject {
    static let shared = BluetoothDeviceManager()

    @Published private(set) var lastEvent: BluetoothDeviceEvent?

    private var connectNotification: IOBluetoothUserNotification?

    private override init() {
        super.init()
    }

    func start() {
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    @objc private func deviceConnected(
        _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
    ) {
        guard Defaults[.enableBluetoothLiveActivity] else { return }
        guard let name = device.name, let address = device.addressString else { return }

        let iconName = Self.iconName(for: device)
        let normalizedAddress = Self.normalizeAddress(address)

        Task { @MainActor in
            // Battery values show up in the registry a moment after connecting.
            try? await Task.sleep(for: .seconds(3))

            let battery = await Task.detached(priority: .utility) {
                Self.batteryInfo(forAddress: normalizedAddress)
            }.value

            self.lastEvent = BluetoothDeviceEvent(
                name: name,
                iconName: iconName,
                batteryPercent: battery.main,
                leftPercent: battery.left,
                rightPercent: battery.right,
                casePercent: battery.case
            )
            BoringViewCoordinator.shared.toggleExpandingView(
                status: true,
                type: .bluetooth,
                value: CGFloat(battery.main ?? battery.left ?? battery.right ?? -1)
            )
        }
    }

    // MARK: - Icon mapping

    private static func iconName(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }

        // Major class 0x04 = audio, 0x05 = peripheral; peripheral minor bits
        // 0x10 = keyboard, 0x20 = pointing device (Bluetooth baseband spec).
        let majorClass = Int(device.deviceClassMajor)
        let minorClass = Int(device.deviceClassMinor)
        switch majorClass {
        case 0x04:
            return "headphones"
        case 0x05:
            return (minorClass & 0x10) != 0 ? "keyboard" : "magicmouse"
        default:
            return "wave.3.right.circle"
        }
    }

    // MARK: - Battery lookup (IOKit registry)

    private nonisolated static func normalizeAddress(_ address: String) -> String {
        address
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .lowercased()
    }

    private nonisolated static func batteryInfo(
        forAddress normalizedAddress: String
    ) -> (main: Int?, left: Int?, right: Int?, case: Int?) {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return (nil, nil, nil, nil) }
        defer { IOObjectRelease(iterator) }

        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }

            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue()
            }

            guard let deviceAddress = property("DeviceAddress") as? String,
                  normalizeAddress(deviceAddress) == normalizedAddress
            else { continue }

            let main = property("BatteryPercent") as? Int
            let left = property("BatteryPercentLeft") as? Int
            let right = property("BatteryPercentRight") as? Int
            let casePercent = property("BatteryPercentCase") as? Int
            return (main, left, right, casePercent)
        }

        return (nil, nil, nil, nil)
    }
}
