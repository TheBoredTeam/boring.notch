//
//  MicrophoneActivityMonitor.swift
//  boringNotch
//
//  Reports whether *something* on this Mac is using the microphone.
//
//  Uses CoreAudio's `kAudioDevicePropertyDeviceIsRunningSomewhere`, which is
//  the same signal behind the orange dot in the menu bar: it is true whenever
//  any process has the input device running, including macOS dictation, and
//  it requires no microphone permission of our own — we are asking about the
//  device's state, never reading a sample.
//
//  Deliberately does not claim to know *which* app, or that it is dictation
//  specifically. CoreAudio does not say, and guessing would be worse than the
//  honest "microphone in use".
//

import AudioToolbox
import Combine
import CoreAudio
import Defaults
import Foundation
import SwiftUI

@MainActor
final class MicrophoneActivityMonitor: ObservableObject {
    static let shared = MicrophoneActivityMonitor()

    @Published private(set) var isMicrophoneActive = false
    /// When the current session started, so the activity can show a duration.
    @Published private(set) var activeSince: Date?

    private var pollTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        Defaults.publisher(.microphoneLiveActivity)
            .sink { [weak self] change in
                Task { @MainActor in
                    if change.newValue { self?.start() } else { self?.stop() }
                }
            }
            .store(in: &cancellables)

        if Defaults[.microphoneLiveActivity] {
            start()
        }
    }

    private func start() {
        guard pollTask == nil else { return }
        // CoreAudio can post a listener for this property, but the listener
        // fires on a private queue and needs careful teardown for what is a
        // single boolean. A 2s poll of one property read is cheaper than the
        // bookkeeping and cannot leak a callback.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let active = Self.isInputDeviceRunning()
                await MainActor.run { self?.update(active: active) }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stop() {
        pollTask?.cancel()
        pollTask = nil
        isMicrophoneActive = false
        activeSince = nil
    }

    private func update(active: Bool) {
        guard active != isMicrophoneActive else { return }
        withAnimation(.smooth) {
            isMicrophoneActive = active
            activeSince = active ? .now : nil
        }
    }

    // MARK: - CoreAudio

    /// True when any process has the default input device running.
    nonisolated static func isInputDeviceRunning() -> Bool {
        guard let deviceID = defaultInputDeviceID() else { return false }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isRunning)
        guard status == noErr else { return false }
        return isRunning != 0
    }

    nonisolated private static func defaultInputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        // kAudioObjectUnknown means there is no input device at all — a Mac
        // mini with nothing plugged in, for instance.
        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }
}
