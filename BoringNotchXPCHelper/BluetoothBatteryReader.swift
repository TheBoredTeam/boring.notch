//
//  BluetoothBatteryReader.swift
//  BoringNotchXPCHelper
//

import Foundation
import IOKit

/// Reads battery levels for paired Bluetooth accessories out of the IORegistry.
///
/// This lives in the unsandboxed helper because the sandboxed app cannot traverse these
/// registry nodes. The property names are undocumented — they are stable in practice but
/// not contractual — so everything here is read defensively and absence is treated as the
/// normal case rather than an error.
enum BluetoothBatteryReader {
    /// Registry classes that expose accessory battery properties. `AppleDeviceManagementHIDEventService`
    /// covers AirPods, Magic Mouse/Keyboard/Trackpad and most Apple accessories.
    private static let serviceClasses = [
        "AppleDeviceManagementHIDEventService",
        "BNBMouseDevice",
        "BNBTrackpadDevice",
        "AppleHSBluetoothDevice",
    ]

    /// Maps our result keys onto the registry property names, most specific first.
    private static let propertyKeys: [(resultKey: String, registryKeys: [String])] = [
        ("left", ["BatteryPercentLeft"]),
        ("right", ["BatteryPercentRight"]),
        ("case", ["BatteryPercentCase"]),
        ("single", ["BatteryPercent", "BatteryPercentCombined"]),
    ]

    /// - Parameter address: hardware address, e.g. `"a1-b2-c3-d4-e5-f6"`.
    /// - Returns: percentages keyed by `single` / `left` / `right` / `case`, or nil when
    ///   the accessory reports nothing.
    static func battery(forAddress address: String) -> [String: NSNumber]? {
        let wanted = normalize(address)
        guard !wanted.isEmpty else { return nil }

        for serviceClass in serviceClasses {
            guard let matching = IOServiceMatching(serviceClass) else { continue }

            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
            else { continue }
            defer { IOObjectRelease(iterator) }

            while case let entry = IOIteratorNext(iterator), entry != IO_OBJECT_NULL {
                defer { IOObjectRelease(entry) }

                guard let properties = copyProperties(of: entry) else { continue }
                guard matchesAddress(properties, wanted: wanted) else { continue }

                if let levels = extractLevels(from: properties) {
                    return levels
                }
            }
        }

        return nil
    }

    // MARK: - Helpers

    private static func copyProperties(of entry: io_registry_entry_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS
        else { return nil }
        return unmanaged?.takeRetainedValue() as? [String: Any]
    }

    /// Accessories spell their address inconsistently (`DeviceAddress`, `BD_ADDR`,
    /// colon- or dash-separated, sometimes as raw bytes), so compare on a normalised form.
    private static func matchesAddress(_ properties: [String: Any], wanted: String) -> Bool {
        for key in ["DeviceAddress", "BD_ADDR", "BluetoothDeviceAddress"] {
            if let string = properties[key] as? String, normalize(string) == wanted {
                return true
            }
            if let data = properties[key] as? Data {
                let hex = data.map { String(format: "%02x", $0) }.joined()
                if hex == wanted { return true }
            }
        }
        return false
    }

    private static func normalize(_ address: String) -> String {
        address.lowercased().filter { $0.isHexDigit }
    }

    private static func extractLevels(from properties: [String: Any]) -> [String: NSNumber]? {
        var levels: [String: NSNumber] = [:]

        for (resultKey, registryKeys) in propertyKeys {
            for registryKey in registryKeys {
                guard let percent = percentValue(properties[registryKey]) else { continue }
                levels[resultKey] = NSNumber(value: percent)
                break
            }
        }

        return levels.isEmpty ? nil : levels
    }

    /// Registry values arrive as NSNumber or occasionally a string; 0 usually means
    /// "not reporting" rather than a flat battery, so treat it as absent.
    private static func percentValue(_ raw: Any?) -> Int? {
        let value: Int
        switch raw {
        case let number as NSNumber: value = number.intValue
        case let string as String: guard let parsed = Int(string) else { return nil }; value = parsed
        default: return nil
        }
        guard (1...100).contains(value) else { return nil }
        return value
    }
}
