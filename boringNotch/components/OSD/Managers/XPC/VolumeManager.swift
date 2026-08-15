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

    private let step: Float32 = 1.0 / 16.0
    // Fallback software if hardware mute is not supported
    private var previousVolumeBeforeMute: Float32 = 0.2
    private var softwareMuted: Bool = false
    private var didInitialFetch = false
    /// Main-side mirror of snapshot.supportsMute for mute-path decisions.
    private var deviceSupportsMute = false

    /// All CoreAudio IPC runs on this serial queue. Every property
    /// read/write is a synchronous round-trip to coreaudiod, and slider
    /// drags can fire change callbacks at 60–120 Hz — none of it belongs
    /// on the main thread (the old implementation ran ~40 IPC calls on
    /// main *per volume event*).
    private let audioQueue = DispatchQueue(label: "com.boringnotch.osd.volume", qos: .userInitiated)

    /// Cached output-device snapshot, rebuilt only when the default output
    /// device changes. AudioObjectPropertyAddress values don't mutate
    /// between calls, so probing Has/GetSize once per device replaces the
    /// ~30 probe calls the old code made on every volume event.
    private struct DeviceSnapshot {
        var deviceID: AudioObjectID = kAudioObjectUnknown
        var volumeElements: [UInt32] = []
        var supportsMute = false
    }
    /// Only touched on audioQueue.
    private var snapshot = DeviceSnapshot()

    /// Writes are coalesced to 15 Hz: a drag gesture produces far more
    /// callbacks than hardware (or the user) benefits from. audioQueue-only.
    private var pendingWriteTarget: Float32?
    private var writeFlushScheduled = false
    private let writeFlushInterval: TimeInterval = 1.0 / 15.0

    /// Volume/mute listeners must be re-registered whenever the output
    /// device changes (the old code registered once at init — after a
    /// device switch, live updates silently stopped).
    private struct ListenerRegistration {
        var deviceID: AudioObjectID
        var address: AudioObjectPropertyAddress
        var block: AudioObjectPropertyListenerBlock
    }
    private var listenerRegistrations: [ListenerRegistration] = []

    private override init() {
        super.init()
        installDeviceChangeListener()
        audioQueue.async { [self] in
            rebuildSnapshotLocked()
            syncFromDeviceLocked()
        }
    }

    var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

    // MARK: - Public Control API

    @MainActor func increase(stepDivisor: Float = 1.0) {
        adjustInSteps(1, stepDivisor: stepDivisor)
    }

    @MainActor func decrease(stepDivisor: Float = 1.0) {
        adjustInSteps(-1, stepDivisor: stepDivisor)
    }

    @MainActor private func adjustInSteps(_ direction: Float32, stepDivisor: Float) {
        let delta = step / Float32(max(stepDivisor, 0.25)) * direction
        commit(target: max(0, min(1, rawVolume + delta)))
    }

    @MainActor func toggleMuteAction() {
        let willBeMuted = !isMuted
        let resultingVolume: Float32 = rawVolume > 0.001 ? rawVolume : previousVolumeBeforeMute

        if willBeMuted {
            if deviceSupportsMute {
                enqueueHardwareMute(true)
            } else {
                if rawVolume > 0.001 { previousVolumeBeforeMute = rawVolume }
                softwareMuted = true
                requestVolumeWrite(0)
            }
            // Hardware mute preserves the underlying volume level.
            publish(volume: deviceSupportsMute ? rawVolume : 0, muted: true, touchDate: true)
            BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: 0)
        } else {
            if deviceSupportsMute {
                enqueueHardwareMute(false)
            } else {
                softwareMuted = false
                requestVolumeWrite(previousVolumeBeforeMute)
            }
            publish(volume: deviceSupportsMute ? rawVolume : resultingVolume, muted: false, touchDate: true)
            BoringViewCoordinator.shared.toggleSneakPeek(
                status: true, type: .volume, value: CGFloat(resultingVolume))
        }
    }

    @MainActor func setAbsolute(_ value: Float32) {
        commit(target: max(0, min(1, value)))
    }

    /// Shared by keys and slider: optimistically publishes the intent (the
    /// OSD bar animates instantly) and defers hardware I/O to the coalesced
    /// writer — listeners confirm the ground truth afterwards.
    @MainActor private func commit(target: Float32) {
        if isMuted && target > 0 {
            // Unmute intent: hardware unmute for mute-capable devices, and
            // the volume write below restores sound on the software path.
            softwareMuted = false
            enqueueHardwareMute(false)
        }
        publish(volume: target, muted: target > 0 ? false : isMuted, touchDate: true)
        if target == 0 && !isMuted {
            // Historical behavior: driving volume to zero engages mute.
            if deviceSupportsMute {
                enqueueHardwareMute(true)
            } else {
                if rawVolume > 0.001 { previousVolumeBeforeMute = rawVolume }
                softwareMuted = true
            }
            publish(volume: target, muted: true, touchDate: true)
        }
        requestVolumeWrite(target)
        BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(target))
    }

    // MARK: - Hardware I/O (audioQueue)

    /// Coalesced writer: runs at most every writeFlushInterval and always
    /// flushes the *latest* requested target.
    private func requestVolumeWrite(_ value: Float32) {
        audioQueue.async { [self] in
            pendingWriteTarget = value
            guard !writeFlushScheduled else { return }
            writeFlushScheduled = true
            audioQueue.asyncAfter(deadline: .now() + writeFlushInterval) { [self] in
                writeFlushScheduled = false
                guard let target = pendingWriteTarget else { return }
                pendingWriteTarget = nil
                writeVolumeLocked(target)
                syncFromDeviceLocked()
            }
        }
    }

    private func enqueueHardwareMute(_ muted: Bool) {
        audioQueue.async { [self] in
            guard snapshot.supportsMute else { return }
            var value: UInt32 = muted ? 1 : 0
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectSetPropertyData(
                snapshot.deviceID, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            syncFromDeviceLocked()
        }
    }

    // MARK: - Snapshot & Listeners (audioQueue)

    /// Removes listeners from the old device, probes the new one once, and
    /// attaches volume/mute listeners to it. CoreAudio delivers every
    /// subsequent change event-driven, so steady state costs zero polling.
    private func rebuildSnapshotLocked() {
        for registration in listenerRegistrations {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(
                registration.deviceID, &address, audioQueue, registration.block)
        }
        listenerRegistrations.removeAll()

        let deviceID = systemOutputDeviceID()
        var snap = DeviceSnapshot(deviceID: deviceID)
        if deviceID != kAudioObjectUnknown {
            snap.volumeElements = [kAudioObjectPropertyElementMain, 1, 2, 3, 4].filter {
                probeScalar(deviceID: deviceID, element: $0)
            }
            snap.supportsMute = probeMute(deviceID: deviceID)
        }
        snapshot = snap

        let supports = snap.supportsMute
        DispatchQueue.main.async { [self] in
            deviceSupportsMute = supports
        }

        guard deviceID != kAudioObjectUnknown else { return }
        // Devices without a master volume only expose per-channel scalars;
        // listen on every element the snapshot validated.
        for element in snap.volumeElements {
            attachListenerLocked(
                deviceID: deviceID, selector: kAudioDevicePropertyVolumeScalar, element: element)
        }
        if snap.supportsMute {
            attachListenerLocked(
                deviceID: deviceID, selector: kAudioDevicePropertyMute,
                element: kAudioObjectPropertyElementMain)
        }
    }

    private func attachListenerLocked(
        deviceID: AudioObjectID, selector: AudioObjectPropertySelector, element: UInt32
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Callbacks are delivered on audioQueue already.
            self?.syncFromDeviceLocked()
        }
        guard AudioObjectAddPropertyListenerBlock(deviceID, &address, audioQueue, block) == noErr
        else { return }
        listenerRegistrations.append(
            ListenerRegistration(deviceID: deviceID, address: address, block: block))
    }

    /// The system-object device-change listener is permanent (registered
    /// once) and is delivered on audioQueue like every other callback.
    private func installDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, audioQueue
        ) { [weak self] _, _ in
            self?.rebuildSnapshotLocked()
            self?.syncFromDeviceLocked()
        }
    }

    /// Reads ground truth using the cached snapshot (no Has/GetSize
    /// probing, unlike the old fetch path) and mirrors it to the published
    /// main-side state.
    private func syncFromDeviceLocked() {
        guard snapshot.deviceID != kAudioObjectUnknown else { return }
        let volume = readVolumeLocked()
        let muted = snapshot.supportsMute ? readMuteLocked() : nil
        DispatchQueue.main.async { [self] in
            applyFromDevice(volume: volume, hardwareMuted: muted)
        }
    }

    @MainActor private func applyFromDevice(volume: Float32?, hardwareMuted: Bool?) {
        let effectiveMuted = hardwareMuted ?? softwareMuted
        let changed =
            (volume != nil && abs(volume! - rawVolume) > 0.0005) || effectiveMuted != isMuted
        // The initial fetch arms change detection without touching the date;
        // only later device-reported changes bring the OSD up.
        if changed && didInitialFetch { lastChangeAt = Date() }
        if let volume { rawVolume = volume }
        isMuted = effectiveMuted
        didInitialFetch = true
    }

    // MARK: - CoreAudio Primitives (audioQueue, snapshot-backed)

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

    private func probeScalar(deviceID: AudioObjectID, element: UInt32) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }
        var sizeNeeded: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sizeNeeded) == noErr
            && sizeNeeded == UInt32(MemoryLayout<Float32>.size)
    }

    private func probeMute(deviceID: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }
        var sizeNeeded: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sizeNeeded) == noErr
            && sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
    }

    private func readVolumeLocked() -> Float32? {
        var collected: [Float32] = []
        for element in snapshot.volumeElements {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            var vol = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(snapshot.deviceID, &addr, 0, nil, &size, &vol) == noErr {
                collected.append(vol)
            }
        }
        guard !collected.isEmpty else { return nil }
        return max(0, min(1, collected.reduce(0, +) / Float32(collected.count)))
    }

    private func writeVolumeLocked(_ value: Float32) {
        guard snapshot.deviceID != kAudioObjectUnknown else { return }
        let newVal = max(0, min(1, value))
        for element in snapshot.volumeElements {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            var val = newVal
            AudioObjectSetPropertyData(
                snapshot.deviceID, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &val)
        }
    }

    private func readMuteLocked() -> Bool? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(snapshot.deviceID, &addr, 0, nil, &size, &muted) == noErr
        else { return nil }
        return muted != 0
    }

    @MainActor private func publish(volume: Float32, muted: Bool, touchDate: Bool) {
        if touchDate { lastChangeAt = Date() }
        rawVolume = volume
        isMuted = muted
    }
}
