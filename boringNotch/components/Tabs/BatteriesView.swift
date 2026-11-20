import SwiftUI
import IOBluetooth
import ObjectiveC
import IOKit.ps
import Darwin

struct AirPodsMaxBattery: Identifiable {
    let id: String
    let name: String
    let percentage: Int?
    let isCharging: Bool?
}

enum AirPodsMaxBatteryReader {
    static func connectedDevices() -> [AirPodsMaxBattery] {
        let powerSources = accessoryPowerSources()
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return devices.filter {
            $0.isConnected() && ($0.name ?? "").localizedCaseInsensitiveContains("AirPods Max")
        }.map { device in
            let name = displayName(of: device)
            let matches = powerSources.filter { ($0[kIOPSNameKey] as? String) == name }
            let powerSource = matches.count == 1 ? matches.first : nil
            return AirPodsMaxBattery(
                id: device.addressString ?? device.name ?? "AirPods Max",
                name: name,
                percentage: percentage(of: device),
                isCharging: powerSource?[kIOPSIsChargingKey] as? Bool
            )
        }.sorted { $0.id < $1.id }
    }

    private typealias PowerSourcesGetter = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?

    private static let copyAccessoryPowerSources: PowerSourcesGetter? = {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType") else { return nil }
        return unsafeBitCast(symbol, to: PowerSourcesGetter.self)
    }()

    private static func accessoryPowerSources() -> [[String: Any]] {
        guard let info = copyAccessoryPowerSources?(4)?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return []
        }
        return sources.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }.filter {
            ($0[kIOPSIsPresentKey] as? Bool) == true && ($0["Part Identifier"] as? String) == "Single"
        }
    }

    private static func displayName(of device: IOBluetoothDevice) -> String {
        let selector = NSSelectorFromString("getDisplayName")
        if device.responds(to: selector),
           let method = class_getInstanceMethod(type(of: device), selector),
           method_getNumberOfArguments(method) == 2 {
            let returnType = method_copyReturnType(method)
            defer { free(returnType) }
            if String(cString: returnType) == "@",
               let name = device.perform(selector)?.takeUnretainedValue() as? String,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
        }
        return device.name ?? "AirPods Max"
    }

    private static func percentage(of device: IOBluetoothDevice) -> Int? {
        let selector = NSSelectorFromString("batteryPercentSingle")
        guard device.responds(to: selector),
              let method = class_getInstanceMethod(type(of: device), selector),
              method_getNumberOfArguments(method) == 2 else { return nil }
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        guard String(cString: returnType) == "C" else { return nil }

        typealias BatteryGetter = @convention(c) (AnyObject, Selector) -> UInt8
        let getter = unsafeBitCast(method_getImplementation(method), to: BatteryGetter.self)
        let value = Int(getter(device, selector))
        return (0...100).contains(value) ? value : nil
    }
}

struct BatteriesView: View {
    @State private var devices: [AirPodsMaxBattery] = []
    @State private var hasRefreshed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !devices.isEmpty {
                ForEach(devices) { device in
                    HStack(spacing: 14) {
                        Image(systemName: "airpodsmax")
                            .font(.system(size: 34))
                            .frame(width: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(device.percentage == nil ? "Battery unavailable" : (device.isCharging == true ? "Charging" : "Connected"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if let percentage = device.percentage {
                            HStack(spacing: 6) {
                                Text("\(percentage)%")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .monospacedDigit()
                                Image(systemName: device.isCharging == true ? "battery.100percent.bolt" : batterySymbol(percentage))
                            }
                            .foregroundStyle(device.isCharging == true ? Color.green : (percentage <= 25 ? Color.red : Color.white))
                        } else {
                            Text("—")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            refreshButton
                .frame(width: 24, height: 24)
                .padding(.trailing, 8)
                .offset(y: -12)
        }
        .overlay {
            if devices.isEmpty {
                Text(hasRefreshed ? "No devices found." : "Checking devices…")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .task {
            while !Task.isCancelled {
                refresh()
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
            }
        }
    }

    private var refreshButton: some View {
        Button(action: refresh) {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
        .help("Refresh battery levels")
        .accessibilityLabel("Refresh battery levels")
    }

    private func refresh() {
        devices = AirPodsMaxBatteryReader.connectedDevices()
        hasRefreshed = true
    }

    private func batterySymbol(_ percentage: Int) -> String {
        switch percentage {
        case 0...10: return "battery.0percent"
        case 11...37: return "battery.25percent"
        case 38...62: return "battery.50percent"
        case 63...87: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
