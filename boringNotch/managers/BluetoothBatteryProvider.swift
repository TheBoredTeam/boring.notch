//
//  BluetoothBatteryProvider.swift
//  boringNotch
//

import Foundation

/// Fetches Bluetooth accessory battery levels through the privileged helper.
///
/// Battery data is genuinely optional: most non-Apple accessories report nothing, and the
/// split left/right/case readings are effectively Apple audio devices only. Callers must
/// render correctly when this returns nil.
@MainActor
final class BluetoothBatteryProvider {
    nonisolated static let shared = BluetoothBatteryProvider()

    /// How long to wait before giving up. The activity should appear promptly whether or
    /// not battery data arrives, so this stays short.
    private static let timeout: Duration = .milliseconds(700)

    nonisolated private init() {}

    func battery(forAddress address: String) async -> BluetoothDeviceBattery? {
        let levels = await withTaskGroup(of: [String: Int]?.self) { group in
            group.addTask {
                await XPCHelperClient.shared.bluetoothDeviceBattery(forAddress: address)
            }
            group.addTask {
                try? await Task.sleep(for: Self.timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        guard let levels else { return nil }

        let battery = BluetoothDeviceBattery(
            single: levels["single"],
            left: levels["left"],
            right: levels["right"],
            casePercent: levels["case"]
        )
        return battery.isEmpty ? nil : battery
    }
}
