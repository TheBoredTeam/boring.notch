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

/// Detailed battery information for AirPods (Left, Right, Case)
struct AirPodsBatteryInfo: Equatable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    
    /// Returns true if any individual battery info is available
    var hasDetailedInfo: Bool {
        left != nil || right != nil || caseLevel != nil
    }
    
    /// Returns the combined/average battery level
    var combinedLevel: Int? {
        let levels = [left, right].compactMap { $0 }
        guard !levels.isEmpty else { return nil }
        return levels.reduce(0, +) / levels.count
    }
}

/// Represents information about a connected audio device
struct AudioDeviceInfo: Equatable {
    let id: AudioDeviceID
    let name: String
    let isBluetoothDevice: Bool
    let isAirPods: Bool
    let deviceType: AudioDeviceType
    var batteryLevel: Int? // Battery level 0-100, nil if unavailable
    var airPodsBattery: AirPodsBatteryInfo? // Detailed battery for AirPods
    
    /// Returns true if this device supports individual battery display (AirPods, AirPods Pro, etc.)
    var supportsIndividualBattery: Bool {
        switch deviceType {
        case .airpods, .airpodsPro, .airpodsGen3, .airpods4:
            return true
        default:
            return false
        }
    }
    
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

/// Manager that monitors audio device connections and disconnections
final class AudioDeviceManager: NSObject, ObservableObject {
    static let shared = AudioDeviceManager()
    
    @Published private(set) var currentOutputDevice: AudioDeviceInfo?
    @Published private(set) var lastConnectedDevice: AudioDeviceInfo?
    @Published private(set) var deviceJustConnected: Bool = false
    
    private var previousDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    
    private override init() {
        super.init()
        setupAudioDeviceListener()
        fetchCurrentOutputDevice()
    }
    
    deinit {
        removeAudioDeviceListener()
    }
    
    func refresh() {
        fetchCurrentOutputDevice()
    }
    
    /// Call this when screen is unlocked to show notification if AirPods are connected
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
    
    /// Persistent mode - keeps the notification visible until stopped
    @Published var isPersistentMode: Bool = false
    
    /// Timer for auto-dismiss
    private var simulationTimer: DispatchWorkItem?
    
    /// Simulates an AirPods Pro connection for testing purposes
    /// Call this from anywhere to test the notification UI without real AirPods
    /// Returns false if simulation is already running
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
    
    /// Stops the simulation
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
    
    /// Simulates different device types for testing
    /// Returns false if simulation is already running
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
    
    private func fetchCurrentOutputDevice() {
        let deviceID = getDefaultOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }
        
        currentOutputDevice = getDeviceInfo(for: deviceID)
        previousDeviceID = deviceID
    }
    
    // MARK: - CoreAudio Helpers
    
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
    
    /// Get detailed AirPods battery info (Left, Right, Case)
    func getAirPodsBatteryInfo(for deviceName: String) -> AirPodsBatteryInfo? {
        return getAirPodsBatteryFromIORegistry(deviceName: deviceName)
    }
    
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
    
    private func getBatteryLevelFromIORegistry(deviceAddress: String?) -> Int? {
        // Try to get battery level from IORegistry
        // This is a simplified approach - battery levels for Bluetooth devices
        // are often available through IORegistry
        
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
