//
//  BluetoothDeviceManager.swift
//  boringNotch
//
//  Created for Bluetooth Input Device Battery Monitoring
//

import AppKit
import Combine
import Defaults
import Foundation
import IOBluetooth

/// Represents a Bluetooth input device (Mouse, Keyboard, Trackpad, etc.)
struct BluetoothInputDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let deviceType: DeviceType
    var batteryLevel: Int?
    var isConnected: Bool
    
    enum DeviceType: String, CaseIterable {
        case mouse = "Mouse"
        case keyboard = "Keyboard"
        case trackpad = "Trackpad"
        case headphones = "Headphones"
        case speaker = "Speaker"
        case other = "Other"
        
        var iconName: String {
            switch self {
            case .mouse: return "magicmouse.fill"
            case .keyboard: return "keyboard.fill"
            case .trackpad: return "rectangle.and.hand.point.up.left.filled"
            case .headphones: return "headphones"
            case .speaker: return "hifispeaker.fill"
            case .other: return "wave.3.right.circle.fill"
            }
        }
    }
}

/// Manager that monitors Bluetooth input devices and their battery levels
final class BluetoothDeviceManager: ObservableObject {
    static let shared = BluetoothDeviceManager()
    
    @Published private(set) var connectedDevices: [BluetoothInputDevice] = []
    @Published private(set) var isRefreshing: Bool = false
    
    private var refreshTimer: Timer?
    
    private init() {
        refreshDevices()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }
    
    deinit { refreshTimer?.invalidate() }
    
    func refreshDevices() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let devices = self?.fetchBluetoothInputDevices() ?? []
            DispatchQueue.main.async {
                self?.connectedDevices = devices
                self?.isRefreshing = false
            }
        }
    }
    
    var devicesWithBattery: [BluetoothInputDevice] {
        connectedDevices.filter { $0.batteryLevel != nil }
    }
    
    private func fetchBluetoothInputDevices() -> [BluetoothInputDevice] {
        var devices: [BluetoothInputDevice] = []
        
        // Get battery info from IORegistry
        let task = Process()
        task.launchPath = "/usr/sbin/ioreg"
        task.arguments = ["-r", "-c", "AppleDeviceManagementHIDEventService", "-a"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
               let array = plist as? [[String: Any]] {
                for entry in array {
                    guard let product = entry["Product"] as? String else { continue }
                    
                    // Skip AirPods (handled by AudioDeviceManager)
                    if product.lowercased().contains("airpods") { continue }
                    
                    let batteryPercent = entry["BatteryPercent"] as? Int
                    let deviceType = Self.determineDeviceType(from: product)
                    
                    // Only include input devices
                    guard [.mouse, .keyboard, .trackpad].contains(deviceType) else { continue }
                    
                    let device = BluetoothInputDevice(
                        id: product,
                        name: product,
                        deviceType: deviceType,
                        batteryLevel: batteryPercent,
                        isConnected: true
                    )
                    devices.append(device)
                }
            }
        } catch {
            NSLog("⚠️ BluetoothDeviceManager: Failed to fetch: \(error)")
        }
        
        return devices
    }
    
    private static func determineDeviceType(from name: String) -> BluetoothInputDevice.DeviceType {
        let lowercaseName = name.lowercased()
        if lowercaseName.contains("mouse") { return .mouse }
        if lowercaseName.contains("keyboard") { return .keyboard }
        if lowercaseName.contains("trackpad") { return .trackpad }
        if lowercaseName.contains("headphone") || lowercaseName.contains("beats") { return .headphones }
        if lowercaseName.contains("speaker") { return .speaker }
        return .other
    }
    
    // MARK: - Debug / Developer Testing
    
    #if DEBUG
    @Published var isSimulating: Bool = false
    
    /// Adds simulated demo devices for testing
    func simulateDemoDevices() {
        isSimulating = true
        NSLog("🧪 BluetoothDeviceManager: Adding simulated demo devices")
        
        let demoDevices: [BluetoothInputDevice] = [
            BluetoothInputDevice(
                id: "demo-mouse",
                name: "Magic Mouse",
                deviceType: .mouse,
                batteryLevel: 72,
                isConnected: true
            ),
            BluetoothInputDevice(
                id: "demo-keyboard",
                name: "Magic Keyboard",
                deviceType: .keyboard,
                batteryLevel: 45,
                isConnected: true
            ),
            BluetoothInputDevice(
                id: "demo-trackpad",
                name: "Magic Trackpad",
                deviceType: .trackpad,
                batteryLevel: 89,
                isConnected: true
            )
        ]
        
        connectedDevices = demoDevices
    }
    
    /// Clears simulated devices and refreshes real devices
    func stopSimulation() {
        NSLog("🧪 BluetoothDeviceManager: Stopping simulation")
        isSimulating = false
        refreshDevices()
    }
    
    /// Adds a single simulated device
    func addSimulatedDevice(type: BluetoothInputDevice.DeviceType, name: String, battery: Int) {
        isSimulating = true
        let device = BluetoothInputDevice(
            id: "demo-\(type.rawValue.lowercased())",
            name: name,
            deviceType: type,
            batteryLevel: battery,
            isConnected: true
        )
        
        // Add to existing devices (don't replace)
        if !connectedDevices.contains(where: { $0.id == device.id }) {
            connectedDevices.append(device)
        }
        NSLog("🧪 BluetoothDeviceManager: Added simulated \(name) with \(battery)% battery")
    }
    #endif
}
