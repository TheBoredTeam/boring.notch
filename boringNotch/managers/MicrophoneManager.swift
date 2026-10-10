//
//  MicrophoneManager.swift
//  boringNotch
//
//  Mutes the default input device and switches between input devices,
//  for the notch's microphone button, mute indicator and shortcut.
//

import AppKit
import Combine
import CoreAudio

struct AudioInputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

/// Published state is only written on the main queue and CoreAudio state
/// only on `audioQueue`, which is what makes the unchecked conformance safe.
final class MicrophoneManager: ObservableObject, @unchecked Sendable {
    static let shared = MicrophoneManager()

    @Published private(set) var isMuted = false
    @Published private(set) var devices: [AudioInputDevice] = []
    @Published private(set) var activeDeviceID: AudioDeviceID = kAudioObjectUnknown

    /// All CoreAudio IPC runs on this serial queue, and every listener is
    /// delivered on it too.
    private let audioQueue = DispatchQueue(label: "com.boringnotch.microphone", qos: .userInitiated)

    /// What the default input device supports, probed once per device.
    private struct DeviceSnapshot {
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var supportsMute = false
        /// Volume controls used to mute a device that has no mute control:
        /// the master alone when there is one, every channel otherwise.
        var volumeElements: [AudioObjectPropertyElement] = []
    }
    private var snapshot = DeviceSnapshot()

    /// Input levels to restore on unmute, per device and volume element.
    private var savedLevels: [AudioDeviceID: [AudioObjectPropertyElement: Float32]] = [:]

    private struct ListenerRegistration {
        var objectID: AudioObjectID
        var address: AudioObjectPropertyAddress
        var block: AudioObjectPropertyListenerBlock
    }
    /// Listeners on the current input device, replaced when it changes.
    private var deviceListeners: [ListenerRegistration] = []

    /// Anything at or below this counts as a silenced input.
    private static let silentLevel: Float32 = 0.001
    /// Restored when a device was already silent before we muted it.
    private static let fallbackLevel: Float32 = 0.8

    private init() {
        audioQueue.async { [self] in
            let system = AudioObjectID(kAudioObjectSystemObject)
            addListenerLocked(system, kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
                self?.rebuildSnapshotLocked()
                self?.refreshDevicesLocked()
            }
            addListenerLocked(system, kAudioHardwarePropertyDevices) { [weak self] in
                self?.refreshDevicesLocked()
            }
            rebuildSnapshotLocked()
            refreshDevicesLocked()
        }
    }

    // MARK: - Public API

    /// Flips the default input device's mute state and shows the mic OSD.
    func toggleMute() {
        audioQueue.async { [self] in
            guard let wasMuted = readMutedLocked() else { return }
            // Some devices apply the change asynchronously, so trust the
            // write here; the listeners report the final state either way.
            let muted = writeMutedLocked(!wasMuted) ? !wasMuted : wasMuted
            DispatchQueue.main.async { [self] in
                isMuted = muted
                NotchUIEventBus.events.send(.sneakPeek(type: .mic, value: muted ? 0 : 1))
            }
        }
    }

    func selectInputDevice(_ deviceID: AudioDeviceID) {
        audioQueue.async {
            // The default-device listener picks up the switch from here.
            if !Self.setDefaultInputDevice(deviceID) {
                Log.general.error("Failed to switch the input device to \(deviceID)")
            }
        }
    }

    func openSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound?input") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Device state (audioQueue)

    /// Re-probes the default input device and moves the listeners over to it.
    private func rebuildSnapshotLocked() {
        for listener in deviceListeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(listener.objectID, &address, audioQueue, listener.block)
        }
        deviceListeners.removeAll()

        let deviceID = Self.defaultInputDevice()
        var snap = DeviceSnapshot(deviceID: deviceID)
        if deviceID != kAudioObjectUnknown {
            snap.supportsMute = Self.isSettable(
                kAudioDevicePropertyMute, of: deviceID, size: MemoryLayout<UInt32>.size)
            let volumes = [kAudioObjectPropertyElementMain, 1, 2, 3, 4].filter {
                Self.isSettable(
                    kAudioDevicePropertyVolumeScalar, of: deviceID, element: $0,
                    size: MemoryLayout<Float32>.size)
            }
            snap.volumeElements = volumes.contains(kAudioObjectPropertyElementMain)
                ? [kAudioObjectPropertyElementMain] : volumes
        }
        snapshot = snap

        // Whatever decides the mute state is watched, so changes made in
        // Sound settings or other apps show up too.
        let watched = snap.supportsMute
            ? [(kAudioDevicePropertyMute, kAudioObjectPropertyElementMain)]
            : snap.volumeElements.map { (kAudioDevicePropertyVolumeScalar, $0) }
        for (selector, element) in watched {
            let listener = addListenerLocked(
                deviceID, selector, scope: kAudioDevicePropertyScopeInput, element: element
            ) { [weak self] in
                self?.syncFromDeviceLocked()
            }
            if let listener { deviceListeners.append(listener) }
        }

        syncFromDeviceLocked()
    }

    private func syncFromDeviceLocked() {
        let deviceID = snapshot.deviceID
        let muted = readMutedLocked() ?? false
        DispatchQueue.main.async { [self] in
            if activeDeviceID != deviceID { activeDeviceID = deviceID }
            if isMuted != muted { isMuted = muted }
        }
    }

    private func refreshDevicesLocked() {
        let found = Self.allDevices()
            .filter(Self.hasInputStreams)
            .compactMap { id in Self.name(of: id).map { AudioInputDevice(id: id, name: $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        DispatchQueue.main.async { [self] in
            if devices != found { devices = found }
        }
    }

    /// nil when the device has neither a mute nor a volume control.
    private func readMutedLocked() -> Bool? {
        let deviceID = snapshot.deviceID
        if snapshot.supportsMute {
            let muted: UInt32? = Self.read(kAudioDevicePropertyMute, of: deviceID)
            return muted.map { $0 != 0 }
        }
        let levels = snapshot.volumeElements.compactMap { element -> Float32? in
            Self.read(kAudioDevicePropertyVolumeScalar, of: deviceID, element: element)
        }
        guard !levels.isEmpty else { return nil }
        return levels.allSatisfy { $0 <= Self.silentLevel }
    }

    /// Returns false if the device rejected the change.
    private func writeMutedLocked(_ muted: Bool) -> Bool {
        let deviceID = snapshot.deviceID
        if snapshot.supportsMute {
            return Self.write(UInt32(muted ? 1 : 0), kAudioDevicePropertyMute, of: deviceID)
        }
        // No mute control: silence the input volume, keeping the levels to
        // put back on unmute.
        var succeeded = true
        for element in snapshot.volumeElements {
            let level: Float32
            if muted {
                if let current: Float32 = Self.read(kAudioDevicePropertyVolumeScalar, of: deviceID, element: element),
                   current > Self.silentLevel {
                    savedLevels[deviceID, default: [:]][element] = current
                }
                level = 0
            } else {
                level = savedLevels[deviceID]?[element] ?? Self.fallbackLevel
            }
            succeeded = Self.write(level, kAudioDevicePropertyVolumeScalar, of: deviceID, element: element) && succeeded
        }
        return succeeded
    }

    @discardableResult
    private func addListenerLocked(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        handler: @escaping () -> Void
    ) -> ListenerRegistration? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        guard AudioObjectAddPropertyListenerBlock(objectID, &address, audioQueue, block) == noErr else {
            return nil
        }
        return ListenerRegistration(objectID: objectID, address: address, block: block)
    }

    // MARK: - CoreAudio

    private static func inputAddress(
        _ selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: element)
    }

    private static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultInputDevice() -> AudioDeviceID {
        var address = globalAddress(kAudioHardwarePropertyDefaultInputDevice)
        var deviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : kAudioObjectUnknown
    }

    private static func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var address = globalAddress(kAudioHardwarePropertyDefaultInputDevice)
        var target = deviceID
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &target) == noErr
    }

    private static func allDevices() -> [AudioDeviceID] {
        var address = globalAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }

        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    /// Outputs are listed too; only devices with input streams can record.
    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = inputAddress(kAudioDevicePropertyStreams)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of deviceID: AudioDeviceID) -> String? {
        var address = globalAddress(kAudioObjectPropertyName)
        var name: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let name = name as String?, !name.isEmpty else { return nil }
        return name
    }

    private static func isSettable(
        _ selector: AudioObjectPropertySelector,
        of deviceID: AudioDeviceID,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        size expectedSize: Int
    ) -> Bool {
        var address = inputAddress(selector, element: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        var size: UInt32 = 0
        return AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr
            && settable.boolValue
            && AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
            && Int(size) == expectedSize
    }

    private static func read<Value: Numeric>(
        _ selector: AudioObjectPropertySelector,
        of deviceID: AudioDeviceID,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Value? {
        var address = inputAddress(selector, element: element)
        var value: Value = 0
        var size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? value : nil
    }

    @discardableResult
    private static func write<Value: Numeric>(
        _ value: Value,
        _ selector: AudioObjectPropertySelector,
        of deviceID: AudioDeviceID,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        var address = inputAddress(selector, element: element)
        var value = value
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Value>.size), pointer)
        }
        return status == noErr
    }
}
