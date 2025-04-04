//
//  AudioDeviceView.swift
//  boringNotch
//
//  Created by Mena Maged on 04/04/2025.
//

import Foundation
import CoreAudio
import AVFoundation

class AudioDeviceMonitor: ObservableObject {
    @Published var outputDeviceName: String = getCurrentOutputDeviceName() ?? "Unknown"

    private var defaultDeviceID = AudioDeviceID(0)

    init() {
        updateOutputDeviceName()
        listenForOutputDeviceChanges()
    }

    private func updateOutputDeviceName() {
        if let name = getCurrentOutputDeviceName() {
            DispatchQueue.main.async {
                self.outputDeviceName = name
            }
        }
    }

    private func listenForOutputDeviceChanges() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

        let status = AudioObjectAddPropertyListenerBlock(systemObjectID, &address, DispatchQueue.global(qos: .default)) { [weak self] _, _ in
            self?.updateOutputDeviceName()
        }

        if status != noErr {
            print("❌ Failed to add output device change listener: \(status)")
        }
    }
}
