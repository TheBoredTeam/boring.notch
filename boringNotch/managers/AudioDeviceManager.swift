//
//  AudioDeviceManager.swift
//  boringNotch
//
//  Created for AirPods Connected Reveal Feature
//

import AppKit
import Combine
import CoreAudio
import Defaults
import Foundation
import IOBluetooth

// MARK: - AirPodsBatteryInfo

/// Detailed battery information for AirPods devices.
///
/// This struct stores individual battery levels for AirPods components:
/// - Left earpiece
/// - Right earpiece
/// - Charging case
///
/// Battery levels are retrieved from macOS IORegistry via `ioreg` command.
///
/// ## Example
/// ```swift
/// let battery = AirPodsBatteryInfo(left: 85, right: 82, caseLevel: 100)
/// if battery.hasDetailedInfo {
///     print("Left: \(battery.left ?? 0)%")
/// }
/// ```
struct AirPodsBatteryInfo: Equatable {
    /// Battery level of the left earpiece (0-100), nil if unavailable
    var left: Int?
    
    /// Battery level of the right earpiece (0-100), nil if unavailable
    var right: Int?
    
    /// Battery level of the charging case (0-100), nil if unavailable
    var caseLevel: Int?
    
    /// Returns true if any individual battery info is available
    var hasDetailedInfo: Bool {
        left != nil || right != nil || caseLevel != nil
    }
    
    /// Returns the combined/average battery level of the earpieces
    var combinedLevel: Int? {
        let levels = [left, right].compactMap { $0 }
        guard !levels.isEmpty else { return nil }
        return levels.reduce(0, +) / levels.count
    }
}

// MARK: - AudioDeviceInfo

/// Represents information about a connected audio output device.
///
/// This struct contains all relevant information about an audio device including
/// its type, connection status, and battery information (for Bluetooth devices).
///
/// ## Properties
/// - `id`: CoreAudio device identifier
/// - `name`: Device display name (e.g., "AirPods Pro")
/// - `isBluetoothDevice`: True for Bluetooth/BLE connections
/// - `isAirPods`: True for any AirPods variant
/// - `deviceType`: Categorized device type for icon selection
/// - `batteryLevel`: Overall battery percentage (if available)
/// - `airPodsBattery`: Detailed L/R/Case battery info (AirPods only)
struct AudioDeviceInfo: Equatable {
    /// CoreAudio device identifier
    let id: AudioDeviceID
    
    /// Device display name as reported by the system
    let name: String
    
    /// True if connected via Bluetooth or Bluetooth LE
    let isBluetoothDevice: Bool
    
    /// True for any AirPods variant (AirPods, Pro, Max, Gen3, 4)
    let isAirPods: Bool
    
    /// Categorized device type for UI display
    let deviceType: AudioDeviceType
    
    /// Overall battery level (0-100), nil if unavailable
    var batteryLevel: Int?
    
    /// Detailed AirPods battery info (Left/Right/Case), nil for non-AirPods
    var airPodsBattery: AirPodsBatteryInfo?
    
    /// Returns true if this device supports individual battery display (AirPods with earpieces)
    var supportsIndividualBattery: Bool {
        switch deviceType {
        case .airpods, .airpodsPro, .airpodsGen3, .airpods4:
            return true
        default:
            return false
        }
    }
    
    // MARK: - AudioDeviceType
    
    /// Categorized audio device types for icon selection and display.
    ///
    /// Device types are determined by analyzing the device name and transport type.
    /// Each type provides appropriate SF Symbol icons for the device and its case.
    enum AudioDeviceType: String {
        case airpodsPro = "AirPods Pro"
        case airpods = "AirPods"
        case airpodsGen3 = "AirPods Gen3"
        case airpods4 = "AirPods 4"
        case airpodsMax = "AirPods Max"
        case beatsHeadphones = "Beats"
        case genericBluetooth = "Bluetooth Audio"
        case builtInSpeaker = "Built-in"
        case other = "Audio Device"
        
        /// SF Symbol name for the device icon
        var iconName: String {
            switch self {
            case .airpodsPro, .airpods, .airpodsGen3, .airpods4:
                return "airpodspro"
            case .airpodsMax:
                return "airpodsmax"
            case .beatsHeadphones:
                return "beats.headphones"
            case .genericBluetooth:
                return "headphones"
            case .builtInSpeaker:
                return "speaker.wave.2.fill"
            case .other:
                return "speaker.wave.2.fill"
            }
        }
        
        /// SF Symbol name for the charging case icon (AirPods variants only)
        var caseIcon: String {
            switch self {
            case .airpodsPro:
                return "airpods.pro.chargingcase.wireless.fill"
            case .airpods:
                return "airpods.chargingcase.wireless.fill"
            case .airpodsGen3:
                return "airpods.gen3.chargingcase.wireless.fill"
            case .airpods4:
                return "airpods.gen4.chargingcase.wireless.fill"
            case .airpodsMax:
                return "airpods.max"
            default:
                return "airpods.chargingcase.wireless.fill"
            }
        }
    }
}

// MARK: - AudioDeviceManager

/// Manages audio device monitoring and Bluetooth connection notifications.
///
/// This singleton class monitors macOS audio output device changes using CoreAudio
/// and displays notifications when Bluetooth devices (especially AirPods) connect.
///
/// ## Features
/// - Real-time monitoring of audio output device changes
/// - Detection of Bluetooth device connections
/// - Battery level retrieval for AirPods (individual L/R/Case levels)
/// - Animated notification display via BoringViewCoordinator
/// - Screen unlock detection for showing connected device info
///
/// ## Usage
/// ```swift
/// // Access the shared instance
/// let manager = AudioDeviceManager.shared
///
/// // Check current device
/// if let device = manager.currentOutputDevice {
///     print("Current: \(device.name)")
/// }
///
/// // Manually refresh
/// manager.refresh()
/// ```
///
/// ## Battery Information
/// Battery levels are retrieved from IORegistry via `ioreg` command.
/// For AirPods, individual battery levels (Left, Right, Case) are available.
final class AudioDeviceManager: NSObject, ObservableObject {
    
    /// Shared singleton instance
    static let shared = AudioDeviceManager()
    
    // MARK: - Published Properties
    
    /// Currently active audio output device
    @Published private(set) var currentOutputDevice: AudioDeviceInfo?
    
    /// Last Bluetooth device that connected (used for notification display)
    @Published private(set) var lastConnectedDevice: AudioDeviceInfo?
    
    /// True when a device just connected and notification should be shown
    @Published private(set) var deviceJustConnected: Bool = false
    
    // MARK: - Private Properties
    
    /// Tracks the previous device ID to detect changes
    private var previousDeviceID: AudioDeviceID = kAudioObjectUnknown
    
    /// CoreAudio property listener block reference
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        setupAudioDeviceListener()
        fetchCurrentOutputDevice()
    }
    
    deinit {
        removeAudioDeviceListener()
    }
    
    // MARK: - Public Methods
    
    /// Manually refreshes the current output device information
    func refresh() {
        fetchCurrentOutputDevice()
    }
    
    /// Checks if a Bluetooth device is connected and shows notification.
    ///
    /// Call this method when the screen is unlocked to display the AirPods
    /// connection notification if Bluetooth audio is already connected.
    ///
    /// - Note: Only shows notification if `showAudioDeviceConnectedNotification` setting is enabled
    func checkAndShowNotificationIfBluetoothConnected() {
        guard Defaults[.showAudioDeviceConnectedNotification] else { return }
        
        let deviceID = getDefaultOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }
        
        if let device = getDeviceInfo(for: deviceID), device.isBluetoothDevice {
            NSLog("🎧 AudioDeviceManager: Screen unlocked with Bluetooth device connected: \(device.name)")
            
            var deviceWithBattery = device
            deviceWithBattery.batteryLevel = getBatteryLevel(for: device.name)
            // Get detailed AirPods battery info if available
            if device.supportsIndividualBattery {
                deviceWithBattery.airPodsBattery = getAirPodsBatteryInfo(for: device.name)
            }
            
            lastConnectedDevice = deviceWithBattery
            deviceJustConnected = true
            
            Task { @MainActor in
                BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .audioDevice)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                self?.deviceJustConnected = false
            }
        }
    }
    
    // MARK: - Debug / Developer Testing
    
    #if DEBUG
    /// Flag to prevent multiple simultaneous test triggers
    @Published var isSimulationRunning: Bool = false
    
    /// Persistent mode - keeps the notification visible until manually stopped
    @Published var isPersistentMode: Bool = false
    
    /// Timer for auto-dismiss of simulation
    private var simulationTimer: DispatchWorkItem?
    
    /// Simulates an AirPods Pro connection for testing the notification UI.
    ///
    /// Use this method to test the connection notification without real AirPods.
    /// Creates a simulated AirPods Pro device with customizable battery level.
    ///
    /// - Parameters:
    ///   - batteryLevel: Simulated overall battery level (0-100). Default is 85.
    ///   - persistent: If true, notification stays visible until `stopSimulation()` is called.
    ///
    /// - Returns: Always returns true (simulation started successfully)
    ///
    /// - Note: Only available in DEBUG builds. Individual battery levels are simulated
    ///         as: Left = batteryLevel, Right = batteryLevel - 3, Case = batteryLevel + 10
    @discardableResult
    func simulateAirPodsConnection(batteryLevel: Int = 85, persistent: Bool = false) -> Bool {
        // Cancel any existing timer
        simulationTimer?.cancel()
        simulationTimer = nil
        
        // If already running, stop first then restart
        if isSimulationRunning {
            stopSimulation()
            // Small delay to allow UI to reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.runSimulation(batteryLevel: batteryLevel, persistent: persistent)
            }
            return true
        }
        
        runSimulation(batteryLevel: batteryLevel, persistent: persistent)
        return true
    }
    
    private func runSimulation(batteryLevel: Int, persistent: Bool) {
        isSimulationRunning = true
        isPersistentMode = persistent
        NSLog("🧪 AudioDeviceManager: Simulating AirPods Pro connection (battery: \(batteryLevel)%, persistent: \(persistent))")
        
        // Simulate individual battery levels (slightly different for realism)
        let simulatedAirPodsBattery = AirPodsBatteryInfo(
            left: batteryLevel,
            right: max(0, batteryLevel - 3),  // Right slightly lower
            caseLevel: min(100, batteryLevel + 10)  // Case slightly higher
        )
        
        let simulatedDevice = AudioDeviceInfo(
            id: 9999,
            name: "AirPods Pro",
            isBluetoothDevice: true,
            isAirPods: true,
            deviceType: .airpodsPro,
            batteryLevel: batteryLevel,
            airPodsBattery: simulatedAirPodsBattery
        )
        
        lastConnectedDevice = simulatedDevice
        deviceJustConnected = true
        
        Task { @MainActor in
            // Pass persistent flag to coordinator to skip its auto-dismiss
            BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .audioDevice, persistent: persistent)
        }
        
        // Only auto-dismiss if not persistent - let coordinator handle it
        if !persistent {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.isPersistentMode else { return }
                self.deviceJustConnected = false
                self.isSimulationRunning = false
                self.simulationTimer = nil
                NSLog("🧪 AudioDeviceManager: Simulation finished, ready for next test")
            }
            simulationTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: workItem)
        }
    }
    
    /// Stops the current simulation and hides the notification.
    ///
    /// Call this method to dismiss a persistent simulation or to
    /// immediately stop an auto-dismissing simulation.
    func stopSimulation() {
        NSLog("🧪 AudioDeviceManager: Stopping simulation")
        
        // Cancel any pending timer
        simulationTimer?.cancel()
        simulationTimer = nil
        
        isPersistentMode = false
        deviceJustConnected = false
        isSimulationRunning = false
        
        Task { @MainActor in
            BoringViewCoordinator.shared.toggleExpandingView(status: false, type: .audioDevice, persistent: false)
        }
    }
    
    /// Simulates a connection for any supported device type.
    ///
    /// Use this method to test notifications for different device types
    /// (AirPods Max, Beats, generic Bluetooth, etc.).
    ///
    /// - Parameters:
    ///   - type: The device type to simulate
    ///   - name: Display name for the simulated device
    ///   - batteryLevel: Optional battery level (0-100)
    ///   - persistent: If true, notification stays until manually stopped
    ///
    /// - Returns: Always returns true
    @discardableResult
    func simulateDeviceConnection(type: AudioDeviceInfo.AudioDeviceType, name: String, batteryLevel: Int? = nil, persistent: Bool = false) -> Bool {
        // Cancel any existing timer
        simulationTimer?.cancel()
        simulationTimer = nil
        
        // If already running, stop first
        if isSimulationRunning {
            stopSimulation()
        }
        
        isSimulationRunning = true
        isPersistentMode = persistent
        NSLog("🧪 AudioDeviceManager: Simulating \(type.rawValue) connection")
        
        let simulatedDevice = AudioDeviceInfo(
            id: 9999,
            name: name,
            isBluetoothDevice: true,
            isAirPods: type == .airpods || type == .airpodsPro || type == .airpodsMax,
            deviceType: type,
            batteryLevel: batteryLevel
        )
        
        lastConnectedDevice = simulatedDevice
        deviceJustConnected = true
        
        Task { @MainActor in
            BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .audioDevice, persistent: persistent)
        }
        
        // Only auto-dismiss if not persistent - let coordinator handle it
        if !persistent {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.isPersistentMode else { return }
                self.deviceJustConnected = false
                self.isSimulationRunning = false
                self.simulationTimer = nil
                NSLog("🧪 AudioDeviceManager: Simulation finished, ready for next test")
            }
            simulationTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: workItem)
        }
        
        return true
    }
    #endif
    
    // MARK: - Audio Device Listener Setup
    
    /// Sets up the CoreAudio property listener for output device changes.
    ///
    /// Registers a listener block that fires when the default audio output device changes.
    /// The listener runs on the main queue and calls `handleDeviceChange()`.
    private func setupAudioDeviceListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        listenerBlock = { [weak self] (_, _) in
            DispatchQueue.main.async {
                self?.handleDeviceChange()
            }
        }
        
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            nil,
            listenerBlock!
        )
        
        if status != noErr {
            NSLog("⚠️ AudioDeviceManager: Failed to add device listener: \(status)")
        }
    }
    
    /// Removes the CoreAudio property listener when the manager is deallocated.
    private func removeAudioDeviceListener() {
        guard let block = listenerBlock else { return }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            nil,
            block
        )
    }
    
    // MARK: - Device Change Handling
    
    /// Handles audio output device changes detected by the CoreAudio listener.
    ///
    /// Determines if a Bluetooth device was just connected (switching from built-in
    /// or another non-Bluetooth device) and triggers the connection notification.
    private func handleDeviceChange() {
        let newDeviceID = getDefaultOutputDeviceID()
        guard newDeviceID != kAudioObjectUnknown else { return }
        
        let newDevice = getDeviceInfo(for: newDeviceID)
        let previousDevice = currentOutputDevice
        
        currentOutputDevice = newDevice
        
        // Check if a Bluetooth device was just connected
        if newDeviceID != previousDeviceID,
           let device = newDevice,
           device.isBluetoothDevice,
           previousDevice?.deviceType == .builtInSpeaker || previousDevice == nil || !previousDevice!.isBluetoothDevice {
            
            NSLog("🎧 AudioDeviceManager: Bluetooth device connected: \(device.name)")
            
            // Try to get battery level
            var deviceWithBattery = device
            deviceWithBattery.batteryLevel = getBatteryLevel(for: device.name)
            // Get detailed AirPods battery info if available
            if device.supportsIndividualBattery {
                deviceWithBattery.airPodsBattery = getAirPodsBatteryInfo(for: device.name)
            }
            
            lastConnectedDevice = deviceWithBattery
            deviceJustConnected = true
            
            Task { @MainActor in
                BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .audioDevice)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                self?.deviceJustConnected = false
            }
        }
        
        previousDeviceID = newDeviceID
    }
    
    /// Fetches and stores the current audio output device without triggering notifications.
    private func fetchCurrentOutputDevice() {
        let deviceID = getDefaultOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }
        
        currentOutputDevice = getDeviceInfo(for: deviceID)
        previousDeviceID = deviceID
    }
    
    // MARK: - CoreAudio Helpers
    
    /// Gets the AudioDeviceID of the current default output device.
    ///
    /// - Returns: The device ID, or `kAudioObjectUnknown` if unavailable
    private func getDefaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = kAudioObjectUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        
        return status == noErr ? deviceID : kAudioObjectUnknown
    }
    
    /// Creates an AudioDeviceInfo struct for the given device ID.
    ///
    /// - Parameter deviceID: CoreAudio device identifier
    /// - Returns: Device info struct, or nil if device ID is unknown
    private func getDeviceInfo(for deviceID: AudioDeviceID) -> AudioDeviceInfo? {
        guard deviceID != kAudioObjectUnknown else { return nil }
        
        let name = getDeviceName(for: deviceID)
        let transportType = getTransportType(for: deviceID)
        let isBluetooth = transportType == kAudioDeviceTransportTypeBluetooth ||
                          transportType == kAudioDeviceTransportTypeBluetoothLE
        
        let deviceType = determineDeviceType(name: name, transportType: transportType)
        let isAirPods = deviceType == .airpods || deviceType == .airpodsPro || deviceType == .airpodsMax
        
        return AudioDeviceInfo(
            id: deviceID,
            name: name,
            isBluetoothDevice: isBluetooth,
            isAirPods: isAirPods,
            deviceType: deviceType,
            batteryLevel: nil
        )
    }
    
    /// Gets the display name for an audio device.
    ///
    /// - Parameter deviceID: CoreAudio device identifier
    /// - Returns: Device name string, or "Unknown Device" if unavailable
    private func getDeviceName(for deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
        return status == noErr ? (name as String) : "Unknown Device"
    }
    
    /// Gets the transport type (Bluetooth, Built-in, etc.) for an audio device.
    ///
    /// - Parameter deviceID: CoreAudio device identifier
    /// - Returns: Transport type constant (e.g., `kAudioDeviceTransportTypeBluetooth`)
    private func getTransportType(for deviceID: AudioDeviceID) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &transportType)
        return status == noErr ? transportType : 0
    }
    
    /// Determines the device type based on name and transport type.
    ///
    /// Uses string matching on the device name to identify specific models.
    /// Order matters - more specific models (AirPods Pro) are checked before generic (AirPods).
    ///
    /// - Parameters:
    ///   - name: Device display name
    ///   - transportType: CoreAudio transport type constant
    /// - Returns: Categorized device type
    private func determineDeviceType(name: String, transportType: UInt32) -> AudioDeviceInfo.AudioDeviceType {
        let lowercaseName = name.lowercased()
        
        // AirPods detection (order matters - check specific models first)
        if lowercaseName.contains("airpods pro") {
            return .airpodsPro
        } else if lowercaseName.contains("airpods max") {
            return .airpodsMax
        } else if lowercaseName.contains("airpods 4") || lowercaseName.contains("airpods (4") {
            return .airpods4
        } else if lowercaseName.contains("airpods 3") || lowercaseName.contains("airpods (3") || lowercaseName.contains("3rd generation") {
            return .airpodsGen3
        } else if lowercaseName.contains("airpods") {
            return .airpods
        }
        
        if lowercaseName.contains("beats") || lowercaseName.contains("powerbeats") ||
           lowercaseName.contains("beatsx") || lowercaseName.contains("solo") ||
           lowercaseName.contains("studio") {
            return .beatsHeadphones
        }
        
        if transportType == kAudioDeviceTransportTypeBluetooth ||
           transportType == kAudioDeviceTransportTypeBluetoothLE {
            return .genericBluetooth
        }
        
        if transportType == kAudioDeviceTransportTypeBuiltIn {
            return .builtInSpeaker
        }
        
        return .other
    }
    
    // MARK: - Bluetooth Battery Level
    
    /// Gets the overall battery level for a Bluetooth device via IOBluetooth.
    ///
    /// Searches paired Bluetooth devices for a name match and queries the IORegistry
    /// for battery information.
    ///
    /// - Parameter deviceName: Name of the audio device to find
    /// - Returns: Battery percentage (0-100), or nil if unavailable
    private func getBatteryLevel(for deviceName: String) -> Int? {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return nil
        }
        
        for device in pairedDevices {
            if let name = device.name, name.lowercased().contains(deviceName.lowercased()) || deviceName.lowercased().contains(name.lowercased()) {
                if device.isConnected() {
                    return getBatteryLevelFromIORegistry(deviceAddress: device.addressString)
                }
            }
        }
        return nil
    }
    
    /// Gets detailed AirPods battery info (Left, Right, Case) from IORegistry.
    ///
    /// Queries `AppleDeviceManagementHIDEventService` for individual battery levels.
    /// Looks for keys like `BatteryPercentLeft`, `BatteryPercentRight`, `BatteryPercentCase`.
    ///
    /// - Parameter deviceName: Name of the AirPods device
    /// - Returns: Battery info struct with L/R/Case levels, or nil if unavailable
    func getAirPodsBatteryInfo(for deviceName: String) -> AirPodsBatteryInfo? {
        return getAirPodsBatteryFromIORegistry(deviceName: deviceName)
    }
    
    /// Internal method to query IORegistry for AirPods battery levels.
    ///
    /// Executes `ioreg -r -c AppleDeviceManagementHIDEventService -a` and parses
    /// the plist output for battery information.
    private func getAirPodsBatteryFromIORegistry(deviceName: String) -> AirPodsBatteryInfo? {
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
                    if let product = entry["Product"] as? String,
                       product.lowercased().contains("airpods") {
                        var info = AirPodsBatteryInfo()
                        info.left = entry["BatteryPercentLeft"] as? Int ?? entry["LeftBatteryPercent"] as? Int
                        info.right = entry["BatteryPercentRight"] as? Int ?? entry["RightBatteryPercent"] as? Int
                        info.caseLevel = entry["BatteryPercentCase"] as? Int ?? entry["CaseBatteryPercent"] as? Int
                        if info.hasDetailedInfo { return info }
                    }
                }
            }
        } catch {
            NSLog("⚠️ AudioDeviceManager: Failed to get AirPods battery: \(error)")
        }
        return nil
    }
    
    /// Gets overall battery level from IORegistry for a Bluetooth device.
    ///
    /// This is a fallback method when individual battery levels aren't available.
    /// Queries for `BatteryPercent` key in the HID event service.
    ///
    /// - Parameter deviceAddress: Bluetooth device address (optional)
    /// - Returns: Battery percentage, or nil if unavailable
    private func getBatteryLevelFromIORegistry(deviceAddress: String?) -> Int? {
        guard let deviceAddress = deviceAddress else { return nil }
        
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
                    if let product = entry["Product"] as? String,
                       product.lowercased().contains("airpods") || product.lowercased().contains("beats"),
                       let batteryPercent = entry["BatteryPercent"] as? Int {
                        return batteryPercent
                    }
                }
            }
        } catch {
            NSLog("⚠️ AudioDeviceManager: Failed to get battery level: \(error)")
        }
        
        // Return a mock value for demo purposes if we can't get real battery
        // In production, this would return nil
        return nil
    }
}
