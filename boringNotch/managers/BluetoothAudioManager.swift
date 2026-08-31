//
//  BluetoothAudioManager.swift
//  boringNotch
//
//  Adapted from Cris2907/not-so-boring-notch.
//

import Combine
import CoreAudio
import Defaults
import Foundation
import IOBluetooth
import IOKit.audio

final class BluetoothAudioManager: NSObject, ObservableObject {
    static let shared = BluetoothAudioManager()

    @Published private(set) var currentOutputDevice: BluetoothAudioDevice?
    @Published private(set) var activeNotificationDevice: BluetoothAudioDevice?
    @Published private(set) var activeProfile = BluetoothHeadphoneProfileStore.fallbackProfile

    private var isStarted = false
    private var audioListenersInstalled = false
    private var didInitialFetch = false
    private var lastSeenOutputSignature: String?
    private var lastNotifiedSignature: String?
    private var lastNotificationDate: Date = .distantPast
    private var refreshWorkItem: DispatchWorkItem?
    private var clearNotificationWorkItem: DispatchWorkItem?
    private var bluetoothConnectNotification: IOBluetoothUserNotification?
    private var bluetoothDisconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    private override init() {
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        installAudioListenersIfNeeded()
        refreshMatchingPreference()
        refreshCurrentOutput(triggerNotification: false)
    }

    func stop() {
        isStarted = false
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        clearNotificationWorkItem?.cancel()
        clearNotificationWorkItem = nil
        removeBluetoothNotifications()
    }

    func refreshMatchingPreference() {
        guard isStarted else { return }
        if Defaults[.useBluetoothDeviceMatching] {
            installBluetoothNotificationsIfNeeded()
        } else {
            removeBluetoothNotifications()
        }
        refreshCurrentOutput(triggerNotification: false)
    }

    private func installAudioListenersIfNeeded() {
        guard !audioListenersInstalled else { return }
        audioListenersInstalled = true

        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refreshCurrentOutput(triggerNotification: true)
        }

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.scheduleOutputRefresh()
        }
    }

    private func installBluetoothNotificationsIfNeeded() {
        guard bluetoothConnectNotification == nil else { return }
        bluetoothConnectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(bluetoothDeviceConnected(_:device:))
        )
    }

    private func removeBluetoothNotifications() {
        bluetoothConnectNotification?.unregister()
        bluetoothConnectNotification = nil
        bluetoothDisconnectNotifications.values.forEach { $0.unregister() }
        bluetoothDisconnectNotifications.removeAll()
    }

    private func scheduleOutputRefresh() {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshCurrentOutput(triggerNotification: true)
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func refreshCurrentOutput(triggerNotification: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshCurrentOutput(triggerNotification: triggerNotification)
            }
            return
        }
        guard isStarted else { return }

        let outputDeviceID = systemOutputDeviceID()
        guard outputDeviceID != kAudioObjectUnknown,
              let audioDevice = makeAudioDevice(from: outputDeviceID)
        else {
            currentOutputDevice = nil
            return
        }

        let enrichedDevice = enrichWithBluetoothMetadata(audioDevice)
        let currentSignature = signature(for: enrichedDevice)
        let outputChanged = currentSignature != lastSeenOutputSignature
        lastSeenOutputSignature = currentSignature
        currentOutputDevice = enrichedDevice

        guard didInitialFetch else {
            didInitialFetch = true
            return
        }

        guard triggerNotification || outputChanged,
              outputChanged,
              Defaults[.showBluetoothHeadphoneNotifications],
              enrichedDevice.isBluetooth else {
            return
        }

        notifyDeviceBecameActive(enrichedDevice)
    }

    private func notifyDeviceBecameActive(_ device: BluetoothAudioDevice) {
        let deviceSignature = signature(for: device)
        let now = Date()

        if lastNotifiedSignature == deviceSignature,
           now.timeIntervalSince(lastNotificationDate) < 10 {
            return
        }

        lastNotifiedSignature = deviceSignature
        lastNotificationDate = now

        let profile = BluetoothHeadphoneProfileStore.profile(for: device)
        activeNotificationDevice = device
        activeProfile = profile

        Task { @MainActor in
            BoringViewCoordinator.shared.toggleSneakPeek(
                status: true,
                type: .bluetooth,
                duration: 2.5,
                icon: profile.symbolName
            )
        }

        clearNotificationWorkItem?.cancel()
        let clearWorkItem = DispatchWorkItem { [weak self] in
            self?.activeNotificationDevice = nil
            self?.activeProfile = BluetoothHeadphoneProfileStore.fallbackProfile
        }
        clearNotificationWorkItem = clearWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: clearWorkItem)
    }

    private func makeAudioDevice(from deviceID: AudioObjectID) -> BluetoothAudioDevice? {
        let name = readStringProperty(
            deviceID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? readStringProperty(
            deviceID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioDevicePropertyScopeOutput
        )

        guard let name else { return nil }

        let transportType = readUInt32Property(
            deviceID: deviceID,
            selector: kAudioDevicePropertyTransportType,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? 0

        return BluetoothAudioDevice(
            audioObjectID: deviceID,
            name: name,
            manufacturer: readStringProperty(
                deviceID: deviceID,
                selector: kAudioObjectPropertyManufacturer,
                scope: kAudioObjectPropertyScopeGlobal
            ),
            modelUID: readStringProperty(
                deviceID: deviceID,
                selector: kAudioDevicePropertyModelUID,
                scope: kAudioObjectPropertyScopeGlobal
            ),
            transportType: transportType,
            bluetoothAddress: nil,
            isBluetooth: transportType == UInt32(kIOAudioDeviceTransportTypeBluetooth),
            detectedAt: Date()
        )
    }

    private func enrichWithBluetoothMetadata(_ audioDevice: BluetoothAudioDevice) -> BluetoothAudioDevice {
        guard Defaults[.useBluetoothDeviceMatching],
              let bluetoothDevice = matchingBluetoothDevice(for: audioDevice)
        else {
            return audioDevice
        }

        registerDisconnectNotification(for: bluetoothDevice)

        return BluetoothAudioDevice(
            audioObjectID: audioDevice.audioObjectID,
            name: audioDevice.name,
            manufacturer: audioDevice.manufacturer,
            modelUID: audioDevice.modelUID,
            transportType: audioDevice.transportType,
            bluetoothAddress: bluetoothDevice.addressString,
            isBluetooth: audioDevice.isBluetooth
                || audioDevice.transportType == UInt32(kIOAudioDeviceTransportTypeWireless),
            detectedAt: audioDevice.detectedAt
        )
    }

    private func matchingBluetoothDevice(for audioDevice: BluetoothAudioDevice) -> IOBluetoothDevice? {
        let pairedDevices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let connectedDevices = pairedDevices.filter { $0.isConnected() }

        if let connectedMatch = firstBluetoothMatch(in: connectedDevices, for: audioDevice) {
            return connectedMatch
        }
        return firstBluetoothMatch(in: pairedDevices, for: audioDevice)
    }

    private func firstBluetoothMatch(
        in devices: [IOBluetoothDevice],
        for audioDevice: BluetoothAudioDevice
    ) -> IOBluetoothDevice? {
        let normalizedAudioName = BluetoothHeadphoneProfileStore.normalize(audioDevice.name)
        guard !normalizedAudioName.isEmpty else { return nil }

        return devices.first { device in
            let normalizedDeviceName = BluetoothHeadphoneProfileStore.normalize(device.name)
            guard normalizedDeviceName.count > 2 else { return false }
            return normalizedAudioName.contains(normalizedDeviceName)
                || normalizedDeviceName.contains(normalizedAudioName)
        }
    }

    private func registerDisconnectNotification(for device: IOBluetoothDevice) {
        guard let address = device.addressString,
              bluetoothDisconnectNotifications[address] == nil else {
            return
        }

        bluetoothDisconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(bluetoothDeviceDisconnected(_:device:))
        )
    }

    @objc private func bluetoothDeviceConnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.registerDisconnectNotification(for: device)
            self?.scheduleOutputRefresh()
        }
    }

    @objc private func bluetoothDeviceDisconnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        DispatchQueue.main.async { [weak self] in
            if let address = device.addressString {
                self?.bluetoothDisconnectNotifications[address]?.unregister()
                self?.bluetoothDisconnectNotifications.removeValue(forKey: address)
            }
            self?.scheduleOutputRefresh()
        }
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

    private func readStringProperty(
        deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else { return nil }

        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &value
        )
        guard status == noErr else { return nil }
        return value?.takeUnretainedValue() as String?
    }

    private func readUInt32Property(
        deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> UInt32? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else { return nil }

        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &value
        )
        return status == noErr ? value : nil
    }

    private func signature(for device: BluetoothAudioDevice) -> String {
        [
            String(device.audioObjectID),
            BluetoothHeadphoneProfileStore.normalize(device.name),
            BluetoothHeadphoneProfileStore.normalize(device.modelUID),
            BluetoothHeadphoneProfileStore.normalize(device.bluetoothAddress),
            String(device.transportType)
        ].joined(separator: "|")
    }
}
