//
//  AudioDeviceManager.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-09.
//
//  Enumerates audio output devices and switches the system default output,
//  mirroring the CoreAudio patterns used by VolumeManager.
//

import AppKit
import Combine
import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let name: String
    let transportType: UInt32

    /// SF Symbol that best represents the device's transport type.
    var iconName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            let lower = name.lowercased()
            if lower.contains("airpods max") { return "airpodsmax" }
            if lower.contains("airpods pro") { return "airpodspro" }
            if lower.contains("airpods") { return "airpods" }
            return "headphones"
        case kAudioDeviceTransportTypeBuiltIn:
            return "laptopcomputer"
        case kAudioDeviceTransportTypeUSB:
            return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "tv"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        default:
            return "hifispeaker"
        }
    }
}

final class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var currentDeviceID: AudioObjectID = kAudioObjectUnknown

    private init() {
        reload()
        setupListeners()
    }

    /// SF Symbol for the currently selected output device.
    var currentDeviceIcon: String {
        outputDevices.first(where: { $0.id == currentDeviceID })?.iconName ?? "hifispeaker"
    }

    /// Re-reads the device list and the current default output device.
    func reload() {
        let devices = Self.fetchOutputDevices()
        let current = Self.defaultOutputDeviceID()
        DispatchQueue.main.async {
            self.outputDevices = devices
            self.currentDeviceID = current
        }
    }

    /// Sets the system default output device.
    func setDefaultOutput(_ deviceID: AudioObjectID) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = deviceID
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &id
        )
        if status == noErr {
            DispatchQueue.main.async { self.currentDeviceID = deviceID }
        }
    }

    // MARK: - Listeners

    private func setupListeners() {
        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &devicesAddr,
            DispatchQueue.global(qos: .utility)
        ) { [weak self] _, _ in
            self?.reload()
        }

        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddr,
            DispatchQueue.global(qos: .utility)
        ) { [weak self] _, _ in
            self?.reload()
        }
    }

    // MARK: - CoreAudio helpers

    private static func defaultOutputDeviceID() -> AudioObjectID {
        var deviceID = kAudioObjectUnknown
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        return deviceID
    }

    private static func fetchOutputDevices() -> [AudioDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &ids
        ) == noErr else { return [] }

        return ids.compactMap { id in
            guard deviceHasOutput(id) else { return nil }
            let name = deviceName(id) ?? "Unknown"
            return AudioDevice(id: id, name: name, transportType: deviceTransportType(id))
        }
    }

    private static func deviceHasOutput(_ id: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &dataSize) == noErr,
            dataSize > 0 else { return false }
        let bufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &dataSize, bufferList) == noErr else {
            return false
        }
        let abl = UnsafeMutableAudioBufferListPointer(
            bufferList.assumingMemoryBound(to: AudioBufferList.self)
        )
        for buffer in abl where buffer.mNumberChannels > 0 {
            return true
        }
        return false
    }

    private static func deviceName(_ id: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name)
        return status == noErr ? (name as String) : nil
    }

    private static func deviceTransportType(_ id: AudioObjectID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport)
        return transport
    }
}
