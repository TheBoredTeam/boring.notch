//
//  AudioDevice.swift
//  boringNotch
//
//  Created by Mena Maged on 04/04/2025.
//

import CoreAudio
import AVFoundation

func getCurrentOutputDeviceName() -> String? {
    var defaultDeviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    let result = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        &defaultDeviceID
    )

    guard result == noErr else { return nil }

    var deviceName: CFString = "" as CFString
    size = UInt32(MemoryLayout<CFString>.size)

    address.mSelector = kAudioDevicePropertyDeviceNameCFString

    let nameResult = AudioObjectGetPropertyData(
        defaultDeviceID,
        &address,
        0,
        nil,
        &size,
        &deviceName
    )

    guard nameResult == noErr else { return nil }

    return deviceName as String
}
