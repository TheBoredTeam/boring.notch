//
//  AudioOutputRouteResolver.swift
//  boringNotch
//
//  Shared output-route to icon mapping used by all OSD/HUD surfaces.
//

import CoreAudio
import CoreGraphics
import Foundation

enum AudioOutputRouteKind: Equatable {
    case builtInSpeaker
    case wiredHeadphones
    case airPods
    case airPodsPro
    case airPodsMax
    case bluetoothHeadphones
    case externalSpeaker
    case unknown
}

final class AudioOutputRouteResolver {
    static let shared = AudioOutputRouteResolver()

    private let stateQueue = DispatchQueue(label: "AudioOutputRouteResolver.state")
    private var cachedRouteKind: AudioOutputRouteKind = .unknown

    func volumeSymbol(for value: CGFloat) -> String {
        let clampedValue = max(0, min(1, value))
        let routeKind = stateQueue.sync { cachedRouteKind }

        switch routeKind {
        case .airPods:
            return "airpods"
        case .airPodsPro:
            return "airpodspro"
        case .airPodsMax:
            return "airpodsmax"
        case .wiredHeadphones, .bluetoothHeadphones:
            return "headphones"
        case .builtInSpeaker, .externalSpeaker, .unknown:
            return speakerSymbol(for: clampedValue)
        }
    }

    private init() {
        refreshCachedRouteKind()
        setupAudioRouteListener()
    }

    private func setupAudioRouteListener() {
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            nil
        ) { [weak self] _, _ in
            self?.refreshCachedRouteKind()
        }
    }

    private func refreshCachedRouteKind() {
        let currentRoute = currentRouteKind()
        stateQueue.sync {
            self.cachedRouteKind = currentRoute
        }
    }

    private func currentRouteKind() -> AudioOutputRouteKind {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return .unknown }

        let deviceName = readStringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName)
        let manufacturer = readStringProperty(
            deviceID: deviceID,
            selector: kAudioObjectPropertyManufacturer
        )
        let transportType = readTransportType(deviceID: deviceID)

        return classifyOutputRoute(
            deviceName: deviceName,
            manufacturer: manufacturer,
            transportType: transportType
        )
    }

    private func systemOutputDeviceID() -> AudioObjectID {
        var defaultDeviceID = kAudioObjectUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultDeviceID
        )
        return status == noErr ? defaultDeviceID : kAudioObjectUnknown
    }

    private func classifyOutputRoute(
        deviceName: String,
        manufacturer _: String,
        transportType: UInt32?
    ) -> AudioOutputRouteKind {
        let normalizedName = deviceName.lowercased()

        if normalizedName.contains("airpods max") {
            return .airPodsMax
        }
        if normalizedName.contains("airpods pro") {
            return .airPodsPro
        }
        if normalizedName.contains("airpods") {
            return .airPods
        }

        let isHeadphonesLike = normalizedName.contains("headphone")
            || normalizedName.contains("headset")
            || normalizedName.contains("earbud")
            || normalizedName.contains("earphone")
            || normalizedName.contains("pods")

        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return isHeadphonesLike ? .wiredHeadphones : .builtInSpeaker
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetoothHeadphones
        case kAudioDeviceTransportTypeUSB:
            return .wiredHeadphones
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return isHeadphonesLike ? .wiredHeadphones : .externalSpeaker
        default:
            if isHeadphonesLike {
                return .wiredHeadphones
            }
            if normalizedName.contains("speaker") || normalizedName.contains("display") {
                return .externalSpeaker
            }
            return .unknown
        }
    }

    private func readTransportType(deviceID: AudioObjectID) -> UInt32? {
        var transportType: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &transportType
        )

        return status == noErr ? transportType : nil
    }

    private func readStringProperty(
        deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: CFString = "" as CFString
        var propertySize: UInt32 = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &value) == noErr
        else {
            return ""
        }

        return value as String
    }

    private func speakerSymbol(for value: CGFloat) -> String {
        switch value {
        case 0:
            return "speaker.slash"
        case 0...0.33:
            return "speaker.wave.1"
        case 0.33...0.66:
            return "speaker.wave.2"
        default:
            return "speaker.wave.3"
        }
    }
}
