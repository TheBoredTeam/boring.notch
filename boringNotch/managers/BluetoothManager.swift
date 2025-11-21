//
//  BluetoothManager.swift
//  boringNotch
//
//  Created on 2025-01-XX.
//

import Foundation
import SwiftUI
import IOBluetooth
import Defaults

// Maps to the root object containing the SPBluetoothDataType
fileprivate struct SPBluetoothDataRoot: Decodable {
    let bluetoothData: [SPBluetoothData]?
    
    private enum CodingKeys: String, CodingKey {
        case bluetoothData = "SPBluetoothDataType"
    }
}

fileprivate struct SPBluetoothData: Decodable {
    let deviceConnected: [SPBluetoothDataDevice]?
    let deviceNotconnected: [SPBluetoothDataDevice]?
    
    enum CodingKeys: String, CodingKey {
        case deviceConnected = "device_connected"
        case deviceNotconnected = "device_not_connected"
    }
}

fileprivate struct SPBluetoothDataDevice: Decodable {
    let name: String?
    let info: SPBluetoothDataDeviceInfo?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dict = try container.decode([String: SPBluetoothDataDeviceInfo].self)

        guard let (key, value) = dict.first else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Expected dictionary with a single key")
            )
        }

        self.name = key
        self.info = value
    }
}

fileprivate struct SPBluetoothDataDeviceInfo: Decodable {
    let adress: String?
    // let deviceBatteryLevelMain: String // - not used
    let minorType: String?
    let productID: String?
    let services: String?
    let vendorID: String?
    
    enum CodingKeys: String, CodingKey {
        case adress = "device_adress"
        case minorType = "device_minorType"
        case productID = "device_productID"
        case services = "device_services"
        case vendorID = "device_vendorID"
    }
}

final class BluetoothManager: NSObject, ObservableObject {
    
    static let shared = BluetoothManager()
    
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Published private(set) var batteryPercentage: Int? = nil
    @Published private(set) var lastBluetoothDevice: IOBluetoothDevice?
    
    private var notificationCenter: IOBluetoothUserNotification?
    private var connectedDevices: [String : String] = [:]
    private var batteryFetchTask: Task<Void, Never>?
    
    private override init() {
        super.init()
        registerForConnect()
    }
    
    deinit {
        notificationCenter?.unregister()
        batteryFetchTask?.cancel()
    }
    
    private func registerForConnect() {
        // Register for Bluetooth notifications
        notificationCenter = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        
        // Initial check
        checkDevices()
    }
    
    private func checkDevices() {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }
        
        let currentConnected = Set(devices.filter { $0.isConnected() }.compactMap { $0.addressString })
        
        // Find connected devices
        for address in currentConnected {
            if let device = devices.first(where: { $0.addressString == address }),
               let address = device.addressString,
               let name = device.name {
                device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
                connectedDevices[address] = name
                
                /*
                let handsFreeDevice = IOBluetoothHandsFreeDevice(device: device, delegate: self)
                handsFreeDevice?.connect() // This attempts to trigger a connection and service discovery
                 */
            }
        }
    }
    
    // MARK: - Device Connection/Disconnection
    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        handleDeviceConnected(device)
    }
    
    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        handleDeviceDisconnected(device)
    }
    
    private func handleDeviceConnected(_ device: IOBluetoothDevice) {
        guard let name = device.name, let address = device.addressString else { return }
        connectedDevices[address] = name
        
        Task { @MainActor in
            device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
            lastBluetoothDevice = device
        }
        startBatteryPolling(for: device)
    }
    
    private func handleDeviceDisconnected(_ device: IOBluetoothDevice) {
        batteryFetchTask?.cancel()
        Task { @MainActor in
            lastBluetoothDevice = device
            batteryPercentage = nil
            coordinator.toggleExpandingView(status: true, type: .bluetooth)
        }
        if let address = device.addressString {
            connectedDevices.removeValue(forKey: address)
        }
    }
    
    // MARK: - Battery Info
    private func startBatteryPolling(for device: IOBluetoothDevice?) {
        batteryFetchTask?.cancel()
        
        guard let device,
              let deviceName = device.name,
              let deviceAddress = device.addressString else { return }
        
        batteryFetchTask = Task.detached { [weak self] in
            guard let self else { return }
            let maxDuration: TimeInterval = 2.0
            let pollingInterval: UInt64 = 100_000_000 // 100ms
            let deadline = Date().addingTimeInterval(maxDuration)
            
            while !Task.isCancelled && Date() < deadline {
                if let percentage = await self.getBatteryPercentageViaPmset(
                    deviceName: deviceName,
                    deviceAddress: deviceAddress
                ) {
                    await MainActor.run {
                        guard self.lastBluetoothDevice?.addressString == deviceAddress else { return }
                        self.batteryPercentage = percentage
                        self.coordinator.toggleExpandingView(status: true, type: .bluetooth)
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: pollingInterval)
            }
            
            await MainActor.run {
                guard self.lastBluetoothDevice?.addressString == deviceAddress else { return }
                self.batteryPercentage = nil
            }
        }
    }
    
    private func getBatteryPercentageViaPmset(deviceName: String, deviceAddress: String?) async -> Int? {
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        
        let task = Process()
        let pipe = Pipe()
        
        // Command to list all attached power sources (including peripherals)
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g", "accps"]
        task.standardOutput = pipe
        
        let fileHandle = pipe.fileHandleForReading
        let data: Data?
        do {
            try task.run()
            task.waitUntilExit()
            data = try fileHandle.readToEnd()
        } catch {
            return nil
        }
    
        guard let data, let output = String(data: data, encoding: .utf8) else { return nil }
        // Example line to look for: " -External-0 (id=XXXXX)  85%; discharging;"
        // We need to parse this output specifically for the device name.
        
        let lines = output
            .components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(trimmedName) }
        
        for line in lines {
            // Use a regex to find the percentage number followed by "%"
            let pattern = "(\\d+)\\%;" // Capture one or more digits before the %;
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(line.startIndex..., in: line)
                if let match = regex.firstMatch(in: line, options: [], range: range) {
                    let percentRange = Range(match.range(at: 1), in: line)!
                    return Int(line[percentRange])
                }
            }
        }
        return nil
    }
    
    // MARK: - Device Icon & Info
    func getDeviceIcon(for device: IOBluetoothDevice?) -> String {
        // Check custom mappings first
        if let device,
           let deviceName = device.name {
            let customMappings = Defaults[.bluetoothDeviceIconMappings]
            for mapping in customMappings {
                if deviceName.localizedCaseInsensitiveContains(mapping.deviceName) {
                    return mapping.sfSymbolName
                }
            }
        }
        
        // Fall back to default logic
        if let device,
           let deviceName = device.name,
           let iconName = sfSymbolForAudioDevice(deviceName) {
            return iconName
        }
        guard let device, let type = getBluetoothDeviceMinorType(device) else {
            return "circle.badge.questionmark"
        }
        
        // just to be sure
        let lowercasedType = type.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch lowercasedType {
        // ----------------------------------------------------------------------
        // 1. PERIPHERAL / HID (Major Class: 0x05)
        // ----------------------------------------------------------------------
        case "keyboard":
            return "keyboard.fill"
        case "mouse", "pointing device":
            return "computermouse.fill"
        case "gamepad", "joystick", "remote control", "gaming controller":
            return "gamecontroller.fill"
        // ----------------------------------------------------------------------
        // 2. AUDIO/VIDEO (Major Class: 0x04)
        // ----------------------------------------------------------------------
        case "headset", "hands-free device", "headphones":
            return "headphones"
        case "loudspeaker", "portable audio device", "car audio":
            return "hifispeaker.fill"
        case "microphone", "camcorder", "video camera", "video conferencing":
            return "speaker.wave.3.fill"
        // ----------------------------------------------------------------------
        // 3. PHONE (Major Class: 0x02)
        // ----------------------------------------------------------------------
        case "cellular", "smart phone", "cordless phone", "modem":
            return "smartphone"
        // ----------------------------------------------------------------------
        // 4. COMPUTER (Major Class: 0x01)
        // ----------------------------------------------------------------------
        case "desktop workstation", "server-class computer", "laptop", "handheld pc/pda", "palm sized pc/pda", "tablet":
            return "desktopcomputer"
        // ----------------------------------------------------------------------
        // 5. WEARABLE (Major Class: 0x07)
        // ----------------------------------------------------------------------
        case "wristwatch", "pager", "jacket", "helmet", "glasses":
            return "watch.analog"
        // ----------------------------------------------------------------------
        // 6. HEALTH / MEDICAL (Major Class: 0x09)
        // ----------------------------------------------------------------------
        case "blood pressure monitor", "thermometer", "weighing scale", "glucose meter", "pulse oximeter", "heart/pulse rate monitor":
            return "circle.badge.questionmark"
        default:
            return "circle.badge.questionmark"
        }
    }
    
    private func getBluetoothDeviceMinorType(_ device: IOBluetoothDevice?) -> String? {
        guard let deviceName = device?.name else { return nil }
        
        let task = Process()
        let pipe = Pipe()
        
        // --- FIX: Use bash to wrap the command and force output flush ---
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Use 'cat' to ensure the output is fully written to the pipe before exit
        let commandString = "/usr/sbin/system_profiler -json SPBluetoothDataType | cat"
        task.arguments = ["-c", commandString]
        
        var environment = ProcessInfo.processInfo.environment
        environment["__CFPREFERENCES_AVOID_DAEMON"] = "1"
        task.environment = environment
        
        task.standardOutput = pipe
        let fileHandle = pipe.fileHandleForReading
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        
        do {
            guard let data = try fileHandle.readToEnd() else {
                return nil
            }
            let rootData = try JSONDecoder().decode(SPBluetoothDataRoot.self, from: data)
            guard let devices = rootData.bluetoothData?.first?.deviceConnected,
                  let device = devices.first(where: {$0.name == deviceName})
            else {
                print("Failed to find 'devices' array or 'device' in JSON structure.")
                return nil
            }
            
            return device.info?.minorType?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            print("JSON Decoding Error: \(error)")
            return nil
        }
    }
    
    private func sfSymbolForAudioDevice(_ deviceName: String) -> String? {
        let name = deviceName.lowercased()

        // ---- Apple AirPods ----
        if name.contains("airpods max") { return "airpodsmax" }
        else if name.contains("airpods pro") { return "airpodspro" }
        else if name.contains("airpods case") { return "airpodschargingcase" }
        else if name.contains("airpods") { return "airpods" }
        // ---- Beats ----
        if name.contains("beats studio buds") { return "beats.studiobuds" }
        else if name.contains("beats solo buds") { return "beats.solobuds" }
        else if name.contains("beats solo") { return "beats.headphones" }
        else if name.contains("beats studio") { return "beats.headphones" }
        else if name.contains("powerbeats pro") { return "beats.powerbeats.pro" }
        else if name.contains("beats fit pro") { return "beats.fitpro" }
        else if name.contains("beats flex") { return "beats.earphones" }
        // ---- General fallback for audio devices ----
        if name.contains("buds") { return "earbuds" }
        if name.contains("headphone") || name.contains("headset") { return "headphones" }
        if name.contains("speaker") { return "hifispeaker.fill" }
        
        // --- Keyboard & Mouse ---
        if name.contains("keyboard") { return "keyboard.fill" }
        if name.contains("mouse") && name.contains("magic") { return "magicmouse.fill" }
        else if name.contains("mouse") { return "computermouse.fill" }
        // ---- Gamepads ----
        if name.contains("gamepad") || name.contains("controller") || name.contains("joy-con") { return "gamecontroller.fill" }
        
        return nil
    }
}
