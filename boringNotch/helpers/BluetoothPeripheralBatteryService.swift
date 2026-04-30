//
//  BluetoothPeripheralBatteryService.swift
//  boringNotch
//

import Foundation

/// Reads peripheral battery level via `pmset` and polls briefly until a value appears or times out.
enum BluetoothPeripheralBatteryService {
    enum PollConfiguration {
        static let maxDuration: TimeInterval = 2.0
        static let pollingIntervalNanoseconds: UInt64 = 100_000_000
    }

    /// Parses `pmset -g accps` for a line matching the device name and returns the percentage.
    static func fetchBatteryPercentageViaPmset(deviceName: String, deviceAddress: String?) async -> Int? {
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let task = Process()
        let pipe = Pipe()

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

        let lines = output
            .components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(trimmedName) }

        for line in lines {
            let pattern = "(\\d+)\\%;"
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

    /// Polls until a percentage is found or `maxDuration` elapses.
    static func pollUntilBatteryPercentageFound(
        deviceName: String,
        deviceAddress: String,
        maxDuration: TimeInterval = PollConfiguration.maxDuration,
        pollingIntervalNanoseconds: UInt64 = PollConfiguration.pollingIntervalNanoseconds
    ) async -> Int? {
        let deadline = Date().addingTimeInterval(maxDuration)

        while !Task.isCancelled && Date() < deadline {
            if let percentage = await fetchBatteryPercentageViaPmset(
                deviceName: deviceName,
                deviceAddress: deviceAddress
            ) {
                return percentage
            }
            try? await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
        }

        return nil
    }
}

/// Async metadata for icon fallback (Bluetooth minor class via XPC helper).
enum BluetoothDeviceMetadata {
    static func fetchMinorDeviceClass(deviceName: String) async -> String? {
        await XPCHelperClient.shared.getBluetoothDeviceMinorClass(with: deviceName)
    }
}
