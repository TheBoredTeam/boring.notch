//
//  MicrophoneManager.swift
//  boringNotch
//

import AppKit
import Combine
import CoreAudio
import Foundation

struct InputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let isCurrentDefault: Bool
}

final class MicrophoneManager: NSObject, ObservableObject {
    static let shared = MicrophoneManager()

    @Published private(set) var isMuted: Bool = false
    @Published private(set) var lastChangeAt: Date = .distantPast
    @Published private(set) var availableInputDevices: [InputDevice] = []

    let visibleDuration: TimeInterval = 1.2

    private var previousInputVolumeBeforeMute: Float32 = 0.8
    private var softwareMuted: Bool = false
    private var didInitialFetch = false
    private var currentInputDeviceID: AudioObjectID = kAudioObjectUnknown
    private let audioQueue = DispatchQueue(label: "boring.notch.audio.microphone", qos: .userInitiated)
    private let audioQueueKey = DispatchSpecificKey<Void>()

    private var defaultInputDeviceListener: AudioObjectPropertyListenerBlock = { _, _ in }
    private var devicesListener: AudioObjectPropertyListenerBlock = { _, _ in }
    private var inputDeviceListener: AudioObjectPropertyListenerBlock = { _, _ in }

    private override init() {
        super.init()
        audioQueue.setSpecific(key: audioQueueKey, value: ())

        defaultInputDeviceListener = { [weak self] _, _ in
            guard let self else { return }
            self.rebindInputDeviceListeners()
            self.fetchCurrentMute()
            self.refreshAvailableInputDevicesInternal()
        }

        devicesListener = { [weak self] _, _ in
            guard let self else { return }
            self.rebindInputDeviceListeners()
            self.fetchCurrentMute()
            self.refreshAvailableInputDevicesInternal()
        }

        inputDeviceListener = { [weak self] _, _ in
            self?.fetchCurrentMute()
        }

        audioQueue.async { [weak self] in
            guard let self else { return }
            self.setupAudioListener()
            self.fetchCurrentMute()
        }
    }

    deinit {
        if DispatchQueue.getSpecific(key: audioQueueKey) != nil {
            removeDefaultInputDeviceListener()
            removeDevicesListener()
            removeInputDeviceListeners(from: currentInputDeviceID)
        } else {
            audioQueue.sync {
                self.removeDefaultInputDeviceListener()
                self.removeDevicesListener()
                self.removeInputDeviceListeners(from: self.currentInputDeviceID)
            }
        }
    }

    var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

    func toggleMuteAction() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.toggleMuteInternal()
            let muted = self.isMutedInternal()
            Task { @MainActor in
                BoringViewCoordinator.shared.toggleSneakPeek(
                    status: true,
                    type: .mic,
                    value: muted ? 0 : 1
                )
            }
        }
    }

    func refresh() {
        audioQueue.async { [weak self] in
            self?.fetchCurrentMute()
        }
    }

    func refreshAvailableInputDevices() {
        audioQueue.async { [weak self] in
            self?.refreshAvailableInputDevicesInternal()
        }
    }

    func setDefaultInputDevice(_ deviceID: AudioObjectID) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            guard self.isInputCapableDevice(deviceID) else {
                print("❌ [MicrophoneManager] Device \(deviceID) is not input-capable")
                return
            }

            var defaultInputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var targetDeviceID = deviceID
            let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

            let status = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultInputAddress,
                0,
                nil,
                dataSize,
                &targetDeviceID
            )

            if status == noErr {
                self.rebindInputDeviceListeners()
                self.fetchCurrentMute()
                self.refreshAvailableInputDevicesInternal()
            } else {
                print("❌ [MicrophoneManager] Failed to set default input device \(deviceID), status: \(status)")
            }
        }
    }

    func openInputSoundSettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.preference.sound?input",
            "x-apple.systempreferences:com.apple.preference.sound",
        ]

        DispatchQueue.main.async {
            for urlString in settingsURLs {
                guard let url = URL(string: urlString) else { continue }
                if NSWorkspace.shared.open(url) {
                    return
                }
            }
        }
    }

    private func setupAudioListener() {
        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            audioQueue,
            defaultInputDeviceListener
        )

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            audioQueue,
            devicesListener
        )

        rebindInputDeviceListeners()
        refreshAvailableInputDevicesInternal()
    }

    private func removeDefaultInputDeviceListener() {
        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            audioQueue,
            defaultInputDeviceListener
        )
    }

    private func removeDevicesListener() {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            audioQueue,
            devicesListener
        )
    }

    private func rebindInputDeviceListeners() {
        let newDeviceID = systemInputDeviceID()
        guard newDeviceID != currentInputDeviceID else { return }

        removeInputDeviceListeners(from: currentInputDeviceID)
        currentInputDeviceID = newDeviceID
        addInputDeviceListeners(to: newDeviceID)
    }

    private func addInputDeviceListeners(to deviceID: AudioObjectID) {
        guard deviceID != kAudioObjectUnknown else { return }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddress) {
            AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, audioQueue, inputDeviceListener)
        }

        for element in [kAudioObjectPropertyElementMain, 1, 2, 3, 4] {
            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &volumeAddress) {
                AudioObjectAddPropertyListenerBlock(
                    deviceID,
                    &volumeAddress,
                    audioQueue,
                    inputDeviceListener
                )
            }
        }
    }

    private func removeInputDeviceListeners(from deviceID: AudioObjectID) {
        guard deviceID != kAudioObjectUnknown else { return }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddress) {
            AudioObjectRemovePropertyListenerBlock(
                deviceID,
                &muteAddress,
                audioQueue,
                inputDeviceListener
            )
        }

        for element in [kAudioObjectPropertyElementMain, 1, 2, 3, 4] {
            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &volumeAddress) {
                AudioObjectRemovePropertyListenerBlock(
                    deviceID,
                    &volumeAddress,
                    audioQueue,
                    inputDeviceListener
                )
            }
        }
    }

    private func systemInputDeviceID() -> AudioObjectID {
        var defaultDeviceID = kAudioObjectUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
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
        if status != noErr {
            return kAudioObjectUnknown
        }
        return defaultDeviceID
    }

    private func refreshAvailableInputDevicesInternal() {
        let defaultInputDeviceID = systemInputDeviceID()
        let devices = allAudioDeviceIDs()

        let inputDevices = devices.compactMap { deviceID -> InputDevice? in
            guard isInputCapableDevice(deviceID) else { return nil }
            let displayName = deviceName(for: deviceID) ?? "Unknown Input"
            return InputDevice(
                id: deviceID,
                name: displayName,
                isCurrentDefault: deviceID == defaultInputDeviceID
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        DispatchQueue.main.async {
            self.availableInputDevices = inputDevices
        }
    }

    private func allAudioDeviceIDs() -> [AudioObjectID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard deviceCount > 0 else { return [] }

        var deviceIDs = [AudioObjectID](repeating: kAudioObjectUnknown, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.filter { $0 != kAudioObjectUnknown }
    }

    private func isInputCapableDevice(_ deviceID: AudioObjectID) -> Bool {
        var streamConfigAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &streamConfigAddress) else { return false }

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID,
            &streamConfigAddress,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return false
        }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        guard AudioObjectGetPropertyData(
            deviceID,
            &streamConfigAddress,
            0,
            nil,
            &dataSize,
            rawBufferList
        ) == noErr else {
            return false
        }

        let audioBufferList = rawBufferList.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let channelCount = buffers.reduce(0) { partial, buffer in
            partial + Int(buffer.mNumberChannels)
        }

        return channelCount > 0
    }

    private func deviceName(for deviceID: AudioObjectID) -> String? {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &nameAddress) else { return nil }

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &nameAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr else { return nil }
        return name as String
    }

    private func fetchCurrentMute() {
        let muted = isMutedInternal()
        DispatchQueue.main.async {
            let didChange = self.isMuted != muted
            if self.didInitialFetch && didChange {
                self.lastChangeAt = Date()
            }
            self.isMuted = muted
            self.didInitialFetch = true
        }
    }

    private func isMutedInternal() -> Bool {
        let deviceID = systemInputDeviceID()
        guard deviceID != kAudioObjectUnknown else {
            return softwareMuted
        }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddress) {
            var sizeNeeded: UInt32 = 0
            if AudioObjectGetPropertyDataSize(deviceID, &muteAddress, 0, nil, &sizeNeeded) == noErr,
               sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
            {
                var muted: UInt32 = 0
                var size = sizeNeeded
                if AudioObjectGetPropertyData(
                    deviceID,
                    &muteAddress,
                    0,
                    nil,
                    &size,
                    &muted
                ) == noErr {
                    softwareMuted = muted != 0
                    return muted != 0
                }
            }
        }

        if let currentInput = readInputVolumeInternal() {
            let fallbackMuted = currentInput <= 0.001
            if !fallbackMuted {
                previousInputVolumeBeforeMute = currentInput
            }
            softwareMuted = fallbackMuted
            return fallbackMuted
        }

        return softwareMuted
    }

    private func toggleMuteInternal() {
        let deviceID = systemInputDeviceID()
        guard deviceID != kAudioObjectUnknown else {
            performSoftwareMuteToggle(currentVolume: readInputVolumeInternal() ?? 0)
            return
        }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(deviceID, &muteAddress) {
            performSoftwareMuteToggle(currentVolume: readInputVolumeInternal() ?? 0)
            return
        }

        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &muteAddress, 0, nil, &sizeNeeded) == noErr,
              sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
        else {
            performSoftwareMuteToggle(currentVolume: readInputVolumeInternal() ?? 0)
            return
        }

        var muted: UInt32 = 0
        var size = sizeNeeded
        guard AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &muted) == noErr
        else {
            performSoftwareMuteToggle(currentVolume: readInputVolumeInternal() ?? 0)
            return
        }

        var newValue: UInt32 = muted == 0 ? 1 : 0
        let status = AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, size, &newValue)
        if status == noErr {
            softwareMuted = newValue != 0
            publish(muted: newValue != 0, touchDate: true)
        } else {
            performSoftwareMuteToggle(currentVolume: readInputVolumeInternal() ?? 0)
        }
    }

    private func performSoftwareMuteToggle(currentVolume: Float32) {
        let currentlyMuted = softwareMuted || currentVolume <= 0.001
        if currentlyMuted {
            let restore = max(0, min(1, previousInputVolumeBeforeMute))
            writeInputVolumeInternal(restore)
            softwareMuted = false
            publish(muted: false, touchDate: true)
        } else {
            if currentVolume > 0.001 {
                previousInputVolumeBeforeMute = currentVolume
            }
            writeInputVolumeInternal(0)
            softwareMuted = true
            publish(muted: true, touchDate: true)
        }
    }

    private func readInputVolumeInternal() -> Float32? {
        let deviceID = systemInputDeviceID()
        if deviceID == kAudioObjectUnknown {
            return nil
        }

        var collected: [Float32] = []
        for element in [kAudioObjectPropertyElementMain, 1, 2, 3, 4] {
            if let value = readValidatedInputScalar(deviceID: deviceID, element: element) {
                collected.append(value)
            }
        }
        return collected.average
    }

    private func writeInputVolumeInternal(_ value: Float32) {
        let deviceID = systemInputDeviceID()
        if deviceID == kAudioObjectUnknown {
            return
        }

        let clamped = max(0, min(1, value))
        var didWrite = false

        if writeValidatedInputScalar(
            deviceID: deviceID,
            element: kAudioObjectPropertyElementMain,
            value: clamped
        ) {
            didWrite = true
        } else {
            for element in [UInt32](1...4) {
                if writeValidatedInputScalar(deviceID: deviceID, element: element, value: clamped) {
                    didWrite = true
                }
            }
        }

        if !didWrite {
            // silent fail
        }
    }

    private func readValidatedInputScalar(deviceID: AudioObjectID, element: UInt32) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &sizeNeeded) == noErr,
              sizeNeeded == UInt32(MemoryLayout<Float32>.size)
        else { return nil }

        var volume = Float32(0)
        var size = sizeNeeded
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        return status == noErr ? volume : nil
    }

    private func writeValidatedInputScalar(
        deviceID: AudioObjectID,
        element: UInt32,
        value: Float32
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &sizeNeeded) == noErr,
              sizeNeeded == UInt32(MemoryLayout<Float32>.size)
        else { return false }

        var valueToWrite = max(0, min(1, value))
        return AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            sizeNeeded,
            &valueToWrite
        ) == noErr
    }

    private func publish(muted: Bool, touchDate: Bool) {
        DispatchQueue.main.async {
            if touchDate {
                self.lastChangeAt = Date()
            }
            self.isMuted = muted
        }
    }
}

extension Array where Element == Float32 {
    fileprivate var average: Float32? { isEmpty ? nil : reduce(0, +) / Float32(count) }
}
