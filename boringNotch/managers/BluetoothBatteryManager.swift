import Foundation
import IOKit

struct BluetoothBatteryInfo: Identifiable {
    let id: String // device address
    let deviceName: String
    let batteryPercent: Int
}

final class BluetoothBatteryManager: ObservableObject {
    static let shared = BluetoothBatteryManager()

    @Published var devices: [BluetoothBatteryInfo] = []

    private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        var devices: [BluetoothBatteryInfo] = []
        var iterator = io_iterator_t()

        guard let matchingDict = IOServiceMatching("AppleDeviceManagementHIDEventService") as? [String: Any] else { return }
        let dict = matchingDict as CFDictionary

        guard IOServiceGetMatchingServices(kIOMainPortDefault, dict, &iterator) == KERN_SUCCESS else { return }

        var object = IOIteratorNext(iterator)
        while object != 0 {
            if let percent = ioregInt(object, key: "BatteryPercent"), percent > 0 {
                let address = ioregString(object, key: "DeviceAddress") ?? ""
                let name = ioregString(object, key: "Product") ?? "Unknown"

                // Deduplicate by address
                if !devices.contains(where: { $0.id == address }) {
                    devices.append(BluetoothBatteryInfo(
                        id: address,
                        deviceName: name,
                        batteryPercent: percent
                    ))
                }
            }
            // Each iterated entry owns a reference that must be released
            IOObjectRelease(object)
            object = IOIteratorNext(iterator)
        }

        IOObjectRelease(iterator)

        DispatchQueue.main.async { self.devices = devices }
    }

    private func ioregInt(_ object: io_object_t, key: String) -> Int? {
        guard let cfVal = IORegistryEntryCreateCFProperty(object, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        return cfVal as? Int
    }

    private func ioregString(_ object: io_object_t, key: String) -> String? {
        guard let cfVal = IORegistryEntryCreateCFProperty(object, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        return cfVal as? String
    }

    deinit { timer?.invalidate() }
}
