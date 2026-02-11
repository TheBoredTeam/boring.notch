//
//  VolumeManager.swift
//  boringNotch
//
//  Created by JeanLouis on 22/08/2025.
//

import AppKit
import Combine
import CoreAudio
import Foundation

final class VolumeManager: NSObject, ObservableObject {
    static let shared = VolumeManager()

    @Published private(set) var rawVolume: Float = 0
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var lastChangeAt: Date = .distantPast

    let visibleDuration: TimeInterval = 1.2

    private var didInitialFetch = false
    private let step: Float32 = 1.0 / 16.0
    // Fallback software if hardware mute is not supported
    private var previousVolumeBeforeMute: Float32 = 0.2
    private var softwareMuted: Bool = false

    private override init() {
        super.init()
        setupAudioListener()
        fetchCurrentVolume()
    }

    var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

    // MARK: - Public Control API
    @MainActor func increase(stepDivisor: Float = 1.0) {
        let divisor = max(stepDivisor, 0.25)
        let delta = step / Float32(divisor)
        let current = readVolumeInternal() ?? rawVolume
        let target = max(0, min(1, current + delta))
        setAbsolute(target)
        BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(target))
    }

    @MainActor func decrease(stepDivisor: Float = 1.0) {
        let divisor = max(stepDivisor, 0.25)
        let delta = step / Float32(divisor)
        let current = readVolumeInternal() ?? rawVolume
        let target = max(0, min(1, current - delta))
        setAbsolute(target)
        BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(target))
    }

    @MainActor func toggleMuteAction() {
        // Determine expected resulting state immediately and show HUD with that value
        let deviceID = systemOutputDeviceID()
        var willBeMuted = false
        var resultingVolume: Float32 = rawVolume

        if deviceID == kAudioObjectUnknown {
            willBeMuted = !softwareMuted
            resultingVolume = willBeMuted ? 0 : previousVolumeBeforeMute
        } else {
            let currentMuted = isMutedInternal()
            willBeMuted = !currentMuted
            resultingVolume = willBeMuted ? 0 : (readVolumeInternal() ?? rawVolume)
        }

        toggleMuteInternal()
        BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(willBeMuted ? 0 : resultingVolume))
    }
    
    func refresh() { fetchCurrentVolume() }

    func adjustRelative(delta: Float32) {
        if isMutedInternal() { toggleMuteInternal() }
        guard let current = readVolumeInternal() else {
            fetchCurrentVolume()
            return
        }
        let target = max(0, min(1, current + delta))
        writeVolumeInternal(target)  
        publish(volume: target, muted: isMutedInternal(), touchDate: true)
    }

    @MainActor func setAbsolute(_ value: Float32) {
        let clamped = max(0, min(1, value))
        let currentlyMuted = isMutedInternal()
        if currentlyMuted && clamped > 0 {
            toggleMuteInternal()
        }

        writeVolumeInternal(clamped)

        if clamped == 0 && !currentlyMuted {
            toggleMuteInternal()
        }

        publish(volume: clamped, muted: isMutedInternal(), touchDate: true)
    }

    // MARK: - CoreAudio Helpers
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
        if status != noErr { return kAudioObjectUnknown }
        return defaultDeviceID
    }

    private func fetchCurrentVolume() {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }
        var volumes: [Float32] = []
        let candidateElements: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2, 3, 4]
        for element in candidateElements {
            if let v = readValidatedScalar(deviceID: deviceID, element: element) {
                volumes.append(v)
            }
        }
        if !volumes.isEmpty {
            let avg = max(0, min(1, volumes.reduce(0, +) / Float32(volumes.count)))
            DispatchQueue.main.async {
                if self.rawVolume != avg {  
                    if self.didInitialFetch {
                        self.lastChangeAt = Date()
                    }
                }
                self.rawVolume = avg
                self.didInitialFetch = true

            }
        }

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddr) {
            var sizeNeeded: UInt32 = 0
            if AudioObjectGetPropertyDataSize(deviceID, &muteAddr, 0, nil, &sizeNeeded) == noErr,
                sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
            {
                var muted: UInt32 = 0
                var mSize = sizeNeeded
                if AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &mSize, &muted) == noErr
                {
                    let newMuted = muted != 0
                    DispatchQueue.main.async {
                        if self.isMuted != newMuted { self.lastChangeAt = Date() }
                        self.isMuted = newMuted
                    }
                }
            }
        }
    }

    private func setupAudioListener() {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }

        var defaultDevAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDevAddr, nil
        ) { _, _ in
            self.fetchCurrentVolume()
        }

        var masterAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &masterAddr) {
            AudioObjectAddPropertyListenerBlock(deviceID, &masterAddr, nil) { _, _ in
                self.fetchCurrentVolume()
            }
        } else {
            for ch in [UInt32(1), UInt32(2)] {
                var chAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: ch
                )
                if AudioObjectHasProperty(deviceID, &chAddr) {
                    AudioObjectAddPropertyListenerBlock(deviceID, &chAddr, nil) { _, _ in
                        self.fetchCurrentVolume()
                    }
                }
            }
        }

        // Mute
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddr) {
            AudioObjectAddPropertyListenerBlock(deviceID, &muteAddr, nil) { _, _ in
                self.fetchCurrentVolume()
            }
        }
    }

    private func readVolumeInternal() -> Float32? {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return nil }
        var collected: [Float32] = []
        for el in [kAudioObjectPropertyElementMain, 1, 2, 3, 4] {
            if let v = readValidatedScalar(deviceID: deviceID, element: el) { collected.append(v) }
        }
        guard !collected.isEmpty else { return nil }
        return collected.reduce(0, +) / Float32(collected.count)
    }

    private func writeVolumeInternal(_ value: Float32) {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return }
        let newVal = max(0, min(1, value))

        var written = false
        if writeValidatedScalar(
            deviceID: deviceID, element: kAudioObjectPropertyElementMain, value: newVal)
        {
            written = true
        } else {
            var any = false
            for el in [UInt32](1...4) {
                if writeValidatedScalar(deviceID: deviceID, element: el, value: newVal) {
                    any = true
                }
            }
            written = any
        }
        if !written {
            // silent fail
        }
    }

    private func isMutedInternal() -> Bool {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return softwareMuted }
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &muteAddr) else { return softwareMuted }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &muteAddr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
        else { return softwareMuted }
        var muted: UInt32 = 0
        var size = sizeNeeded
        if AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted) == noErr {
            return muted != 0
        }
        return softwareMuted
    }

    private func toggleMuteInternal() {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown {
            performSoftwareMuteToggle(currentVolume: rawVolume)
            return
        }
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(deviceID, &muteAddr) {
            let currentVol = readVolumeInternal() ?? rawVolume
            performSoftwareMuteToggle(currentVolume: currentVol)
            return
        }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &muteAddr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
        else {
            let currentVol = readVolumeInternal() ?? rawVolume
            performSoftwareMuteToggle(currentVolume: currentVol)
            return
        }
        var muted: UInt32 = 0
        var size = sizeNeeded
        if AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted) == noErr {
            var newVal: UInt32 = muted == 0 ? 1 : 0
            AudioObjectSetPropertyData(deviceID, &muteAddr, 0, nil, size, &newVal)
            let vol = readVolumeInternal() ?? rawVolume
            publish(volume: vol, muted: newVal != 0, touchDate: true)
        } else {
            let currentVol = readVolumeInternal() ?? rawVolume
            performSoftwareMuteToggle(currentVolume: currentVol)
        }
    }

    private func performSoftwareMuteToggle(currentVolume: Float32) {
        if softwareMuted {
            let restore = max(0, min(1, previousVolumeBeforeMute))
            writeVolumeInternal(restore)
            softwareMuted = false
            publish(volume: restore, muted: false, touchDate: true)
        } else {
            if currentVolume > 0.001 { previousVolumeBeforeMute = currentVolume }
            writeVolumeInternal(0)
            softwareMuted = true
            publish(volume: 0, muted: true, touchDate: true)
        }
    }

    private func readValidatedScalar(deviceID: AudioObjectID, element: UInt32) -> Float32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return nil }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<Float32>.size)
        else { return nil }
        var vol = Float32(0)
        var size = sizeNeeded
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol)
        return status == noErr ? vol : nil
    }

    private func writeValidatedScalar(deviceID: AudioObjectID, element: UInt32, value: Float32)
        -> Bool
    {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<Float32>.size)
        else { return false }
        var val = value
        return AudioObjectSetPropertyData(deviceID, &addr, 0, nil, sizeNeeded, &val) == noErr
    }

    private func publish(volume: Float32, muted: Bool, touchDate: Bool) {
        DispatchQueue.main.async {
            if touchDate { self.lastChangeAt = Date() }
            self.rawVolume = volume
            self.isMuted = muted
        }
    }
}

final class MicrophoneManager: NSObject, ObservableObject {
    static let shared = MicrophoneManager()

    @Published private(set) var isMuted: Bool = false
    @Published private(set) var lastChangeAt: Date = .distantPast

    let visibleDuration: TimeInterval = 1.2

    private var previousInputVolumeBeforeMute: Float32 = 0.8
    private var softwareMuted: Bool = false
    private var currentInputDeviceID: AudioObjectID = kAudioObjectUnknown
    private let audioQueue = DispatchQueue(label: "boring.notch.audio.microphone", qos: .userInitiated)
    private let audioQueueKey = DispatchSpecificKey<Void>()

    private var defaultInputDeviceListener: AudioObjectPropertyListenerBlock = { _, _ in }
    private var inputDeviceListener: AudioObjectPropertyListenerBlock = { _, _ in }

    private override init() {
        super.init()
        audioQueue.setSpecific(key: audioQueueKey, value: ())

        defaultInputDeviceListener = { [weak self] _, _ in
            guard let self else { return }
            self.rebindInputDeviceListeners()
            self.fetchCurrentMute()
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
            removeInputDeviceListeners(from: currentInputDeviceID)
        } else {
            audioQueue.sync {
                self.removeDefaultInputDeviceListener()
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

        rebindInputDeviceListeners()
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

    private func fetchCurrentMute() {
        let muted = isMutedInternal()
        DispatchQueue.main.async {
            if self.isMuted != muted {
                self.lastChangeAt = Date()
            }
            self.isMuted = muted
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
