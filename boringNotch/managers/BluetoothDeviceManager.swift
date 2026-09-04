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

// MARK: - BluetoothInputDevice

/// Represents a Bluetooth input device such as Magic Mouse, Magic Keyboard, or Magic Trackpad.
///
/// This struct holds information about a connected Bluetooth HID (Human Interface Device),
/// including its name, type, battery level, and connection status.
///
/// - Note: AirPods and other audio devices are handled separately by `AudioDeviceManager`.
struct BluetoothInputDevice: Identifiable, Equatable {
    /// Unique identifier for the device (typically the product name)
    let id: String
    
    /// Display name of the device (e.g., "Magic Mouse")
    let name: String
    
    /// The type/category of the device
    let deviceType: DeviceType
    
    /// Current battery level as percentage (0-100), nil if unavailable
    var batteryLevel: Int?
    
    /// Whether the device is currently connected
    var isConnected: Bool
    
    /// Supported Bluetooth input device types
    enum DeviceType: String, CaseIterable {
        case mouse = "Mouse"
        case keyboard = "Keyboard"
        case trackpad = "Trackpad"
        case headphones = "Headphones"
        case speaker = "Speaker"
        case other = "Other"
        
        /// SF Symbol icon name for this device type
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

// MARK: - BluetoothDeviceManager

/// Monitors and manages Bluetooth input devices (Mouse, Keyboard, Trackpad) and their battery levels.
///
/// This singleton manager periodically scans for connected Bluetooth HID devices using macOS IORegistry
/// and exposes their battery information for display in the UI.
///
/// ## Features
/// - Automatic refresh every 60 seconds
/// - Manual refresh capability
/// - Filters out audio devices (handled by `AudioDeviceManager`)
/// - Debug simulation mode for testing without real devices
///
/// ## Usage
/// ```swift
/// // Access connected devices
/// let devices = BluetoothDeviceManager.shared.connectedDevices
///
/// // Get only devices with battery info
/// let devicesWithBattery = BluetoothDeviceManager.shared.devicesWithBattery
///
/// // Manual refresh
/// BluetoothDeviceManager.shared.refreshDevices()
/// ```
final class BluetoothDeviceManager: ObservableObject {
    
    /// Shared singleton instance
    static let shared = BluetoothDeviceManager()
    
    /// List of currently connected Bluetooth input devices
    @Published private(set) var connectedDevices: [BluetoothInputDevice] = []
    
    /// Indicates whether a device refresh is currently in progress
    @Published private(set) var isRefreshing: Bool = false
    
    /// Timer for periodic device refresh (every 60 seconds)
    private var refreshTimer: Timer?
    
    // MARK: - Initialization
    
    private init() {
        refreshDevices()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }
    
    deinit { refreshTimer?.invalidate() }
    
    // MARK: - Public API
    
    /// Manually triggers a refresh of the connected device list.
    ///
    /// This method fetches device information from IORegistry on a background thread
    /// and updates `connectedDevices` on the main thread.
    ///
    /// - Note: If a refresh is already in progress, this call is ignored.
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
    
    /// Returns only devices that have battery level information available.
    ///
    /// Use this computed property to filter out devices where battery status
    /// could not be determined.
    var devicesWithBattery: [BluetoothInputDevice] {
        connectedDevices.filter { $0.batteryLevel != nil }
    }
    
    // MARK: - Private Methods
    
    /// Fetches Bluetooth input devices from macOS IORegistry.
    ///
    /// This method executes `ioreg` command to query `AppleDeviceManagementHIDEventService`
    /// which contains battery information for connected Bluetooth HID devices.
    ///
    /// - Returns: Array of discovered `BluetoothInputDevice` objects
    private func fetchBluetoothInputDevices() -> [BluetoothInputDevice] {
        var devices: [BluetoothInputDevice] = []
        
        // Query IORegistry for HID device battery information
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
                    
                    // Skip AirPods - they are handled by AudioDeviceManager
                    if product.lowercased().contains("airpods") { continue }
                    
                    let batteryPercent = entry["BatteryPercent"] as? Int
                    let deviceType = Self.determineDeviceType(from: product)
                    
                    // Only include input devices (mouse, keyboard, trackpad)
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
            NSLog("⚠️ BluetoothDeviceManager: Failed to fetch devices from IORegistry: \(error)")
        }
        
        return devices
    }
    
    /// Determines the device type based on the product name.
    ///
    /// Uses simple string matching to categorize devices. Apple's Magic devices
    /// typically include "Mouse", "Keyboard", or "Trackpad" in their product names.
    ///
    /// - Parameter name: The product name from IORegistry
    /// - Returns: The determined `DeviceType`
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
    /// Indicates whether simulated devices are currently being displayed
    @Published var isSimulating: Bool = false
    
    /// Populates the device list with simulated demo devices for UI testing.
    ///
    /// Creates three demo devices: Magic Mouse (72%), Magic Keyboard (45%), and Magic Trackpad (89%).
    /// Useful for testing the UI without having real Bluetooth devices connected.
    ///
    /// - Note: Only available in DEBUG builds
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
    
    /// Stops the simulation and refreshes to show real connected devices.
    ///
    /// Call this method to clear simulated devices and return to displaying
    /// actual Bluetooth device information.
    ///
    /// - Note: Only available in DEBUG builds
    func stopSimulation() {
        NSLog("🧪 BluetoothDeviceManager: Stopping simulation")
        isSimulating = false
        refreshDevices()
    }
    
    /// Adds a single simulated device to the device list.
    ///
    /// Use this method to add individual test devices with custom parameters.
    /// The device is added to the existing list without replacing other devices.
    ///
    /// - Parameters:
    ///   - type: The type of device to simulate
    ///   - name: Display name for the device
    ///   - battery: Battery level percentage (0-100)
    ///
    /// - Note: Only available in DEBUG builds
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
