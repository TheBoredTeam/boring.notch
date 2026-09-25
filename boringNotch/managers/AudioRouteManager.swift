//
//  AudioRouteManager.swift
//  boringNotch
//
//  Lists the Mac's audio output devices and switches the system default
//  between them, for the compact player's media-output button.
//
//  Adapted from Atoll's AudioRouteManager
//  (https://github.com/Ebullioscopic/Atoll, GPL-3.0, itself a boring.notch
//  fork).
//
//  Distinct from AudioOutputRouteResolver, which only classifies the
//  *current* route into an icon for the OSD. This one enumerates every
//  device and can change which is active.
//

import Combine
import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32

    /// Name first, transport second: a name match is more specific than the
    /// transport ("AirPods Pro" over Bluetooth beats a generic headphones
    /// glyph), and matches how macOS's own output menu labels things.
    var iconName: String {
        let normalized = name.lowercased()

        if normalized.contains("airpods max") { return "airpodsmax" }
        if normalized.contains("airpods pro") { return "airpodspro" }
        if normalized.contains("airpods") { return "airpods" }
        if normalized.contains("macbook") { return Self.macSymbol }
        if normalized.contains("homepod") { return "homepod" }
        if normalized.contains("headphone") || normalized.contains("headset") || normalized.contains("beats") {
            return "headphones"
        }
        if normalized.contains("display") || normalized.contains("monitor") { return "display" }

        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return normalized.contains("speaker") ? "hifispeaker" : "headphones"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI:
            return "tv"
        case kAudioDeviceTransportTypeUSB:
            return "hifispeaker"
        case kAudioDeviceTransportTypeBuiltIn:
            return Self.macSymbol
        default:
            return "speaker.wave.2"
        }
    }

    /// Mac glyph (open lid with camera notch); "laptopcomputer" is the
    /// generic clamshell without the notch.
    static let macSymbol = "macbook"

    /// The headphone jack also reports `kAudioDeviceTransportTypeBuiltIn`,
    /// so the speakers and the "External Headphones" jack are split by name.
    enum Category {
        case builtIn
        case builtInOther
        case wireless
        case wired
        case bluetooth
        case other

        var sourceGroup: Int {
            switch self {
            case .builtIn: return 0
            case .builtInOther: return 1
            case .wireless: return 2
            case .wired: return 3
            case .bluetooth: return 4
            case .other: return 5
            }
        }
    }

    var category: Category {
        let normalized = name.lowercased()

        if normalized.contains("airpods") { return .bluetooth }
        if normalized.contains("macbook") { return .builtIn }
        if normalized.contains("homepod") { return .wireless }
        if normalized.contains("airplay") { return .wireless }

        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            // The Mac's own speakers vs. the headphone jack / built-in mic —
            // both report BuiltIn, so the name decides.
            if normalized.contains("headphone") || normalized.contains("headset") {
                return .builtInOther
            }
            if normalized.contains("display") || normalized.contains("monitor") {
                return .wired
            }
            return .builtIn
        case kAudioDeviceTransportTypeAirPlay:
            return .wireless
        case kAudioDeviceTransportTypeUSB,
            kAudioDeviceTransportTypeHDMI,
            kAudioDeviceTransportTypeDisplayPort,
            kAudioDeviceTransportTypeVirtual:
            return .wired
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        default:
            if normalized.contains("bluetooth") || normalized.contains("wireless") { return .bluetooth }
            if normalized.contains("headphone") || normalized.contains("headset")
                || normalized.contains("earbud") || normalized.contains("earphone") {
                return .builtInOther
            }
            if normalized.contains("speaker") || normalized.contains("display") || normalized.contains("monitor") {
                return .wired
            }
            return .other
        }
    }

    var sourceGroup: Int { category.sourceGroup }
}

@MainActor
final class AudioRouteManager: ObservableObject {
    static let shared = AudioRouteManager()

    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var activeDeviceID: AudioDeviceID = 0

    var activeDevice: AudioOutputDevice? {
        devices.first { $0.id == activeDeviceID }
    }

    /// CoreAudio property reads block, so they stay off the main thread —
    /// the picker opens from a click and shouldn't stutter the notch.
    private let queue = DispatchQueue(label: "boringNotch.AudioRouteManager")

    private init() {}

    func refreshDevices() {
        queue.async { [weak self] in
            guard let self else { return }
            let defaultID = Self.fetchDefaultOutputDevice()
            let found = Self.fetchOutputDeviceIDs().compactMap(Self.makeDevice)
            // Apple's output-menu order: source groups, alphabetical within
            // each; the active device is not pinned to the top.
            let sorted = found.sorted { lhs, rhs in
                if lhs.sourceGroup != rhs.sourceGroup { return lhs.sourceGroup < rhs.sourceGroup }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            Task { @MainActor in
                self.activeDeviceID = defaultID
                self.devices = sorted
            }
        }
    }

    func select(_ device: AudioOutputDevice) {
        queue.async { [weak self] in
            guard Self.setDefaultOutputDevice(device.id) else { return }
            Task { @MainActor in
                self?.activeDeviceID = device.id
                self?.refreshDevices()
            }
        }
    }

    // MARK: - CoreAudio

    private static func fetchDefaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : 0
    }

    @discardableResult
    private static func setDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var target = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &target
        ) == noErr
    }

    private static func fetchOutputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        // Every device is returned, inputs included — keep only the ones
        // that actually have output streams, or the picker would offer
        // microphones as places to send audio.
        return ids.filter(hasOutputStreams)
    }

    private static func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return false
        }
        return size > 0
    }

    private static func makeDevice(_ deviceID: AudioDeviceID) -> AudioOutputDevice? {
        guard let name = stringProperty(deviceID, kAudioObjectPropertyName), !name.isEmpty else {
            return nil
        }
        return AudioOutputDevice(id: deviceID, name: name, transportType: transportType(deviceID))
    }

    private static func stringProperty(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return value as String?
    }

    private static func transportType(_ deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return 0
        }
        return value
    }
}
