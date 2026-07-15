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

private let kVirtualMainVolumeSelector: AudioObjectPropertySelector = 0x766D7663 // 'vmvc'
private let kVirtualMainMuteSelector: AudioObjectPropertySelector = 0x766D6D63 // 'vmmc'

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

    private var listenedDeviceID: AudioObjectID = kAudioObjectUnknown
    private var volumeListenerAddresses: [AudioObjectPropertyAddress] = []
    private var muteListenerAddress: AudioObjectPropertyAddress?
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var didRegisterDefaultDeviceListener = false

    private override init() {
        super.init()
        setupAudioListener()
        fetchCurrentVolume()
    }

    var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

    var canControlVolume: Bool {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return false }
        return hasVirtualMainVolume(deviceID: deviceID)
            || readValidatedScalar(deviceID: deviceID, element: kAudioObjectPropertyElementMain) != nil
            || readValidatedScalar(deviceID: deviceID, element: 1) != nil
    }

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
        // Determine expected resulting state immediately and show OSD with that value
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

        if let v = readVolumeInternal() {
            let clamped = max(0, min(1, v))
            DispatchQueue.main.async {
                if self.rawVolume != clamped {
                    if self.didInitialFetch {
                        self.lastChangeAt = Date()
                    }
                }
                self.rawVolume = clamped
                self.didInitialFetch = true
            }
        }

        let newMuted = isMutedInternal()
        DispatchQueue.main.async {
            if self.isMuted != newMuted { self.lastChangeAt = Date() }
            self.isMuted = newMuted
        }
    }

    private func setupAudioListener() {
        if !didRegisterDefaultDeviceListener {
            var defaultDevAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &defaultDevAddr, nil
            ) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.bindDeviceListeners()
                    self?.fetchCurrentVolume()
                }
            }
            didRegisterDefaultDeviceListener = true
        }
        bindDeviceListeners()
    }

    private func bindDeviceListeners() {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }
        if deviceID == listenedDeviceID { return }

        unbindDeviceListeners()
        listenedDeviceID = deviceID

        let volumeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.fetchCurrentVolume()
        }
        volumeListenerBlock = volumeBlock

        var virtualAddr = virtualMainVolumeAddress()
        if AudioObjectHasProperty(deviceID, &virtualAddr) {
            AudioObjectAddPropertyListenerBlock(deviceID, &virtualAddr, nil, volumeBlock)
            volumeListenerAddresses.append(virtualAddr)
        } else {
            var masterAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(deviceID, &masterAddr) {
                AudioObjectAddPropertyListenerBlock(deviceID, &masterAddr, nil, volumeBlock)
                volumeListenerAddresses.append(masterAddr)
            } else {
                for ch in [UInt32(1), UInt32(2)] {
                    var chAddr = AudioObjectPropertyAddress(
                        mSelector: kAudioDevicePropertyVolumeScalar,
                        mScope: kAudioDevicePropertyScopeOutput,
                        mElement: ch
                    )
                    if AudioObjectHasProperty(deviceID, &chAddr) {
                        AudioObjectAddPropertyListenerBlock(deviceID, &chAddr, nil, volumeBlock)
                        volumeListenerAddresses.append(chAddr)
                    }
                }
            }
        }

        var muteAddr = preferredMuteAddress(deviceID: deviceID)
        if AudioObjectHasProperty(deviceID, &muteAddr) {
            let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.fetchCurrentVolume()
            }
            muteListenerBlock = muteBlock
            AudioObjectAddPropertyListenerBlock(deviceID, &muteAddr, nil, muteBlock)
            muteListenerAddress = muteAddr
        }
    }

    private func unbindDeviceListeners() {
        guard listenedDeviceID != kAudioObjectUnknown else { return }
        if let volumeBlock = volumeListenerBlock {
            for var addr in volumeListenerAddresses {
                AudioObjectRemovePropertyListenerBlock(listenedDeviceID, &addr, nil, volumeBlock)
            }
        }
        volumeListenerAddresses.removeAll()
        volumeListenerBlock = nil
        if var muteAddr = muteListenerAddress, let muteBlock = muteListenerBlock {
            AudioObjectRemovePropertyListenerBlock(listenedDeviceID, &muteAddr, nil, muteBlock)
        }
        muteListenerAddress = nil
        muteListenerBlock = nil
        listenedDeviceID = kAudioObjectUnknown
    }

    private func virtualMainVolumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kVirtualMainVolumeSelector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func virtualMainMuteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kVirtualMainMuteSelector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func hasVirtualMainVolume(deviceID: AudioObjectID) -> Bool {
        var addr = virtualMainVolumeAddress()
        return AudioObjectHasProperty(deviceID, &addr)
    }

    private func preferredMuteAddress(deviceID: AudioObjectID) -> AudioObjectPropertyAddress {
        var virtual = virtualMainMuteAddress()
        if AudioObjectHasProperty(deviceID, &virtual) {
            return virtual
        }
        return AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func readVolumeInternal() -> Float32? {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return nil }

        if let v = readVirtualMainVolume(deviceID: deviceID) {
            return v
        }
        if let v = readValidatedScalar(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return v
        }
        var channels: [Float32] = []
        for el in [UInt32(1), UInt32(2)] {
            if let v = readValidatedScalar(deviceID: deviceID, element: el) {
                channels.append(v)
            }
        }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Float32(channels.count)
    }

    private func writeVolumeInternal(_ value: Float32) {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return }
        let newVal = max(0, min(1, value))

        if writeVirtualMainVolume(deviceID: deviceID, value: newVal) {
            return
        }
        if writeValidatedScalar(
            deviceID: deviceID, element: kAudioObjectPropertyElementMain, value: newVal)
        {
            return
        }
        for el in [UInt32(1), UInt32(2)] {
            _ = writeValidatedScalar(deviceID: deviceID, element: el, value: newVal)
        }
    }

    private func readVirtualMainVolume(deviceID: AudioObjectID) -> Float32? {
        var addr = virtualMainVolumeAddress()
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

    private func writeVirtualMainVolume(deviceID: AudioObjectID, value: Float32) -> Bool {
        var addr = virtualMainVolumeAddress()
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }
        var settable: DarwinBoolean = false
        if AudioObjectIsPropertySettable(deviceID, &addr, &settable) != noErr || !settable.boolValue {
            return false
        }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<Float32>.size)
        else { return false }
        var val = value
        return AudioObjectSetPropertyData(deviceID, &addr, 0, nil, sizeNeeded, &val) == noErr
    }

    private func isMutedInternal() -> Bool {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return softwareMuted }
        var muteAddr = preferredMuteAddress(deviceID: deviceID)
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
        var muteAddr = preferredMuteAddress(deviceID: deviceID)
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
