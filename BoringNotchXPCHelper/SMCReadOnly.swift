//
//  SMCReadOnly.swift
//  BoringNotchXPCHelper
//
//  Read-only SMC access adapted from Stats by Serhiy Mytrovtsiy:
//  https://github.com/exelban/stats (MIT License)
//

import Darwin
import Foundation
import IOKit

private enum SMCCommand: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case readKeyInfo = 9
}

private struct SMCKeyData {
    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuLimit: UInt32 = 0
        var gpuLimit: UInt32 = 0
        var memoryLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var version = Version()
    var limitData = LimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

final class SMCReadOnly {
    static let shared = SMCReadOnly()

    private var connection: io_connect_t = 0
    private let lock = NSLock()

    private init() {
        let matching = IOServiceMatching("AppleSMC")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            connection = 0
            return
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func averageCPUTemperature() -> Double? {
        let values = cpuTemperatureKeys.compactMap { value(for: $0) }
            .filter { $0 >= 10 && $0 <= 120 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func value(for key: String) -> Double? {
        guard key.utf8.count == 4 else { return nil }

        lock.lock()
        defer { lock.unlock() }

        guard connection != 0, let value = read(key: key) else { return nil }

        switch value.type {
        case "ui8 ":
            return value.bytes.first.map(Double.init)
        case "ui16":
            guard value.bytes.count >= 2 else { return nil }
            return Double(UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
        case "ui32":
            guard value.bytes.count >= 4 else { return nil }
            let raw = UInt32(value.bytes[0]) << 24
                | UInt32(value.bytes[1]) << 16
                | UInt32(value.bytes[2]) << 8
                | UInt32(value.bytes[3])
            return Double(raw)
        case "sp78":
            guard value.bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
            return Double(raw) / 256
        case "flt ":
            guard value.bytes.count >= MemoryLayout<Float>.size else { return nil }
            var raw: Float = 0
            withUnsafeMutableBytes(of: &raw) { destination in
                destination.copyBytes(from: value.bytes.prefix(MemoryLayout<Float>.size))
            }
            return Double(raw)
        case "fpe2":
            guard value.bytes.count >= 2 else { return nil }
            return Double((Int(value.bytes[0]) << 6) + (Int(value.bytes[1]) >> 2))
        default:
            return nil
        }
    }

    private func read(key: String) -> (type: String, bytes: [UInt8])? {
        var input = SMCKeyData()
        var output = SMCKeyData()

        input.key = fourCharacterCode(key)
        input.data8 = SMCCommand.readKeyInfo.rawValue

        guard call(&input, output: &output) == kIOReturnSuccess, output.result == 0 else {
            return nil
        }

        let dataSize = Int(output.keyInfo.dataSize)
        guard dataSize > 0, dataSize <= 32 else { return nil }
        let dataType = fourCharacterString(output.keyInfo.dataType)

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SMCCommand.readBytes.rawValue
        output = SMCKeyData()

        guard call(&input, output: &output) == kIOReturnSuccess, output.result == 0 else {
            return nil
        }

        var rawBytes = output.bytes
        let bytes = withUnsafeBytes(of: &rawBytes) { buffer in
            Array(buffer.prefix(dataSize))
        }
        guard bytes.contains(where: { $0 != 0 }) else { return nil }
        return (dataType, bytes)
    }

    private func call(_ input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(
            connection,
            UInt32(SMCCommand.kernelIndex.rawValue),
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )
    }

    private func fourCharacterCode(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func fourCharacterString(_ value: UInt32) -> String {
        String(bytes: [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ], encoding: .utf8) ?? ""
    }

    private var cpuTemperatureKeys: [String] {
        let brand = cpuBrandString

        if brand.contains("M5") {
            return [
                "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K",
                "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d",
                "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"
            ]
        }
        if brand.contains("M4") {
            return [
                "Te05", "Te0S", "Te09", "Te0H",
                "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"
            ]
        }
        if brand.contains("M3") {
            return [
                "Te05", "Te0L", "Te0P", "Te0S",
                "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
                "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"
            ]
        }
        if brand.contains("M2") {
            return [
                "Tp1h", "Tp1t", "Tp1p", "Tp1l",
                "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"
            ]
        }
        if brand.contains("M1") {
            return [
                "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D",
                "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"
            ]
        }
        return ["TC0D", "TC0E", "TC0F", "TC0H", "TC0P", "TCAD"]
    }

    private var cpuBrandString: String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else {
            return ""
        }
        return String(cString: bytes)
    }
}
