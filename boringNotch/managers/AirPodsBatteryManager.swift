//
//  AirPodsBatteryManager.swift
//  boringNotch
//

import Foundation
import Defaults
import IOBluetooth
import CoreAudio

final class AirPodsBatteryManager {
    static let shared = AirPodsBatteryManager()

    private let queue = DispatchQueue(label: "theboringteam.boringnotch.airpods-battery", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastSnapshot: AirPodsBatterySnapshot?
    private var lastEmitDate: Date = .distantPast

    var onUpdate: ((AirPodsBatterySnapshot) -> Void)?

    private init() {}

    func startMonitoring() {
        guard timer == nil else { return }
        refresh(force: true)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.refresh(force: false)
        }
        timer.resume()
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }

    func refresh(force: Bool = false) {
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            if !force, now.timeIntervalSince(self.lastEmitDate) < 4 {
                return
            }
            let snapshot = self.readSnapshot()
            if snapshot == self.lastSnapshot, !force {
                self.lastEmitDate = now
                return
            }
            self.lastSnapshot = snapshot
            self.lastEmitDate = now
            DispatchQueue.main.async {
                self.onUpdate?(snapshot)
            }
        }
    }

    private func readSnapshot() -> AirPodsBatterySnapshot {
        guard Defaults[.showAirPodsBattery] else {
            return AirPodsBatterySnapshot(devices: [], statusMessage: nil)
        }

        let report = readSystemProfilerBluetoothReport()
        if let report {
            let activeOutputName = currentDefaultOutputDeviceName()
            let devices = buildDevices(from: report, activeOutputName: activeOutputName)
            if devices.isEmpty {
                return AirPodsBatterySnapshot(
                    devices: [],
                    statusMessage: noConnectedAirPodsMessage(report: report)
                )
            }
            return AirPodsBatterySnapshot(devices: devices, statusMessage: nil)
        }

        if let connected = connectedAirPodsFromIOBluetooth() {
            let status = connected.isEmpty
                ? "No connected AirPods detected"
                : "Battery details unavailable in this environment"
            return AirPodsBatterySnapshot(devices: connected, statusMessage: status)
        }

        return AirPodsBatterySnapshot(
            devices: [],
            statusMessage: "AirPods battery unavailable"
        )
    }

    private func readSystemProfilerBluetoothReport() -> [[String: Any]]? {
        // Preferred: ask the non-sandboxed XPC helper (the main app is sandboxed
        // and may not be able to spawn system_profiler directly).
        if let json = fetchBluetoothJSONViaXPCHelper(),
           let data = json.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           !array.isEmpty {
            // Preserve duplicates (e.g. classic + BLE companion records share a
            // name). system_profiler represents them as an array of single-key
            // dictionaries.
            let wrappers: [[String: Any]] = array.map { item in
                let name = item["name"] as? String ?? "Unknown"
                var info: [String: Any] = ["device_address": item["address"] as? String ?? name]
                if let v = item["left"] { info["device_batteryLevelLeft"] = v }
                if let v = item["right"] { info["device_batteryLevelRight"] = v }
                if let v = item["case"] { info["device_batteryLevelCase"] = v }
                if let v = item["minorType"] { info["device_minorType"] = v }
                if let v = item["vendorID"] { info["device_vendorID"] = v }
                if let v = item["productID"] { info["device_productID"] = v }
                if let v = item["serialLeft"] { info["device_serialNumberLeft"] = v }
                if let v = item["serialRight"] { info["device_serialNumberRight"] = v }
                return [name: info]
            }
            return [["device_connected": wrappers]]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["SPBluetoothDataType"] as? [[String: Any]] else {
            return nil
        }
        return entries
    }

    private func fetchBluetoothJSONViaXPCHelper() -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        Task.detached {
            result = await XPCHelperClient.shared.bluetoothDevicesBatteryJSON()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3)
        return result
    }

    private func buildDevices(from entries: [[String: Any]], activeOutputName: String?) -> [AirPodsBatteryDevice] {
        var bestByAddress: [String: AirPodsBatteryDevice] = [:]
        var bestScoreByAddress: [String: Int] = [:]
        var bestByNameKey: [String: AirPodsBatteryDevice] = [:]
        var bestScoreByNameKey: [String: Int] = [:]

        for entry in entries {
            collectDevices(from: entry["device_connected"], activeOutputName: activeOutputName, bestByAddress: &bestByAddress, bestScoreByAddress: &bestScoreByAddress, bestByNameKey: &bestByNameKey, bestScoreByNameKey: &bestScoreByNameKey)
        }

        var merged: [String: AirPodsBatteryDevice] = bestByAddress
        for (key, device) in bestByNameKey {
            if merged.values.contains(where: { nameKey(for: $0.name) == key }) {
                continue
            }
            merged[key] = device
        }

        // Coalesce duplicate records for the same AirPods (e.g. classic + BLE
        // companion entries with different addresses). Prefer the record with
        // left/right data and fill missing case battery from companions.
        var coalescedByName: [String: AirPodsBatteryDevice] = [:]
        for device in merged.values {
            let key = nameKey(for: device.name)
            if let existing = coalescedByName[key] {
                coalescedByName[key] = mergeAirPods(primary: existing, secondary: device)
            } else {
                coalescedByName[key] = device
            }
        }

        return coalescedByName.values
            .filter { $0.isConnected && (isLikelyAirPods(name: $0.name) || $0.isActiveAudioOutput || $0.hasBatteryData) }
            .sorted { lhs, rhs in
                if lhs.hasBatteryData != rhs.hasBatteryData { return lhs.hasBatteryData }
                if lhs.isActiveAudioOutput != rhs.isActiveAudioOutput { return lhs.isActiveAudioOutput }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func collectDevices(
        from value: Any?,
        activeOutputName: String?,
        bestByAddress: inout [String: AirPodsBatteryDevice],
        bestScoreByAddress: inout [String: Int],
        bestByNameKey: inout [String: AirPodsBatteryDevice],
        bestScoreByNameKey: inout [String: Int]
    ) {
        guard let wrappers = value as? [[String: Any]] else { return }
        for wrapper in wrappers {
            for (deviceName, rawInfo) in wrapper {
                guard let info = rawInfo as? [String: Any] else { continue }
                guard let device = makeDevice(name: deviceName, info: info, activeOutputName: activeOutputName) else {
                    continue
                }
                let score = score(for: device, info: info)
                let normalizedAddress = normalizeAddress(device.address)
                if !normalizedAddress.isEmpty, normalizedAddress != "unknown" {
                    if score >= (bestScoreByAddress[normalizedAddress] ?? Int.min) {
                        bestScoreByAddress[normalizedAddress] = score
                        bestByAddress[normalizedAddress] = device
                    }
                } else {
                    let key = nameKey(for: device.name)
                    if score >= (bestScoreByNameKey[key] ?? Int.min) {
                        bestScoreByNameKey[key] = score
                        bestByNameKey[key] = device
                    }
                }
            }
        }
    }

    private func makeDevice(name: String, info: [String: Any], activeOutputName: String?) -> AirPodsBatteryDevice? {
        guard isLikelyAirPods(name: name, info: info) else { return nil }

        let address = (info["device_address"] as? String) ?? name
        let left = parsePercent(info["device_batteryLevelLeft"])
        let right = parsePercent(info["device_batteryLevelRight"])
        let caseBattery = parsePercent(info["device_batteryLevelCase"]) ?? parsePercent(info["device_batteryLevelMain"])
        let isActiveOutput = isActiveOutput(name: name, activeOutputName: activeOutputName)

        return AirPodsBatteryDevice(
            name: name,
            address: address,
            isConnected: true,
            isActiveAudioOutput: isActiveOutput,
            leftBattery: left,
            rightBattery: right,
            caseBattery: caseBattery,
            leftIsCharging: nil,
            rightIsCharging: nil,
            caseIsCharging: nil
        )
    }

    private func score(for device: AirPodsBatteryDevice, info: [String: Any]) -> Int {
        var score = 0
        if device.leftBattery != nil { score += 3 }
        if device.rightBattery != nil { score += 3 }
        if device.caseBattery != nil { score += 1 }
        if info["device_serialNumberLeft"] != nil { score += 2 }
        if info["device_serialNumberRight"] != nil { score += 2 }
        if device.isActiveAudioOutput { score += 1 }
        return score
    }

    private func noConnectedAirPodsMessage(report: [[String: Any]]) -> String {
        for entry in report {
            if let notConnected = entry["device_not_connected"] as? [[String: Any]] {
                for wrapper in notConnected {
                    for (name, rawInfo) in wrapper {
                        let info = rawInfo as? [String: Any]
                        if isLikelyAirPods(name: name, info: info) {
                            return "No connected AirPods detected"
                        }
                    }
                }
            }
        }
        return "No connected AirPods detected"
    }

    private func connectedAirPodsFromIOBluetooth() -> [AirPodsBatteryDevice]? {
        let raw = IOBluetoothDevice.pairedDevices() ?? []
        let paired = raw.compactMap { $0 as? IOBluetoothDevice }
        guard !paired.isEmpty else { return [] }

        let activeOutputName = currentDefaultOutputDeviceName()
        let connected = paired.filter { $0.isConnected() && isLikelyAirPodsIOBluetooth(device: $0) }
        return connected.map { device in
            let name = device.nameOrAddress ?? "AirPods"
            return AirPodsBatteryDevice(
                name: name,
                address: device.addressString ?? name,
                isConnected: true,
                isActiveAudioOutput: isActiveOutput(name: device.name, activeOutputName: activeOutputName),
                leftBattery: nil,
                rightBattery: nil,
                caseBattery: nil,
                leftIsCharging: nil,
                rightIsCharging: nil,
                caseIsCharging: nil
            )
        }
    }

    private func isLikelyAirPods(name: String, info: [String: Any]? = nil) -> Bool {
        if name.localizedCaseInsensitiveContains("airpods") {
            return true
        }
        if let minorType = info?["device_minorType"] as? String,
           minorType.localizedCaseInsensitiveContains("headphone"),
           let vendor = info?["device_vendorID"] as? String,
           vendor.contains("0x004C") || vendor.localizedCaseInsensitiveContains("apple") {
            return name.localizedCaseInsensitiveContains("airpod") || minorType.localizedCaseInsensitiveContains("headphone")
        }
        return false
    }

    private func isLikelyAirPodsIOBluetooth(device: IOBluetoothDevice) -> Bool {
        let name = device.nameOrAddress ?? ""
        if isLikelyAirPods(name: name) { return true }
        let cod = Int(device.classOfDevice)
        let minor = (cod >> 2) & 0x3F
        // Conservative: Apple audio devices with AirPods-like naming handled above.
        // Minor class signals are noisy across transports; keep name-focused.
        _ = minor
        return false
    }

    private func isActiveOutput(name: String?, activeOutputName: String?) -> Bool {
        guard let active = activeOutputName, !active.isEmpty, let name, !name.isEmpty else {
            return false
        }
        return active.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains(active)
    }

    private func currentDefaultOutputDeviceName() -> String? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }

        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString?>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let nameStatus = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, ptr)
        }
        guard nameStatus == noErr else { return nil }
        return name as String
    }


    private func mergeAirPods(primary: AirPodsBatteryDevice, secondary: AirPodsBatteryDevice) -> AirPodsBatteryDevice {
        let primaryHasLR = primary.leftBattery != nil || primary.rightBattery != nil
        let secondaryHasLR = secondary.leftBattery != nil || secondary.rightBattery != nil
        var base = (secondaryHasLR && !primaryHasLR) ? secondary : primary
        let other = (base.address == primary.address) ? secondary : primary
        if base.leftBattery == nil { base.leftBattery = other.leftBattery }
        if base.rightBattery == nil { base.rightBattery = other.rightBattery }
        if base.caseBattery == nil { base.caseBattery = other.caseBattery }
        if base.leftIsCharging == nil { base.leftIsCharging = other.leftIsCharging }
        if base.rightIsCharging == nil { base.rightIsCharging = other.rightIsCharging }
        if base.caseIsCharging == nil { base.caseIsCharging = other.caseIsCharging }
        return base
    }

    private func parsePercent(_ value: Any?) -> Int? {
        guard let string = value as? String else { return nil }
        let digits = string.filter { $0.isNumber }
        guard let intValue = Int(digits), (0...100).contains(intValue) else { return nil }
        return intValue
    }

    private func normalizeAddress(_ value: String) -> String {
        value
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private func nameKey(for name: String) -> String {
        name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
