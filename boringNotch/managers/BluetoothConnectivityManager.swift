//
//  BluetoothConnectivityManager.swift
//  boringNotch
//

import Defaults
import Foundation
import IOBluetooth

/// A Bluetooth device as far as the notch is concerned.
struct BluetoothDeviceInfo: Equatable, Identifiable {
    /// The hardware address, which is stable across renames — unlike the name.
    let address: String
    var name: String
    var battery: BluetoothDeviceBattery?

    var id: String { address }
}

/// Battery readings for a Bluetooth accessory. Every field is optional because most
/// devices report none of them, and only Apple audio devices report the split ones.
struct BluetoothDeviceBattery: Equatable {
    var single: Int?
    var left: Int?
    var right: Int?
    var casePercent: Int?

    var isEmpty: Bool {
        single == nil && left == nil && right == nil && casePercent == nil
    }
}

/// Shows an activity in the notch when a Bluetooth accessory connects or disconnects.
///
/// ## Limitations
/// - Uses IOBluetooth, which reports *classic* Bluetooth connections. BLE-only
///   peripherals (many mice and keyboards) may not produce a connect notification here.
///   There is no public API that reports BLE accessory connections without pairing to
///   them as a CoreBluetooth central, which is not appropriate for already-paired
///   system devices.
/// - Battery levels come from the privileged helper and are only broadly available on
///   Apple audio accessories. Absence of battery data is normal, not an error.
@MainActor
final class BluetoothConnectivityManager: ObservableObject {
    nonisolated static let shared = BluetoothConnectivityManager()

    /// Devices in the activity currently being shown.
    @Published private(set) var activeDevices: [BluetoothDeviceInfo] = []
    @Published private(set) var isDisconnection: Bool = false

    /// Addresses we already consider connected, so a repeat notification for a device
    /// that never went away does not show the activity again.
    private var connectedAddresses: Set<String> = []

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    /// Devices seen since the debounce window opened, coalesced into one activity so
    /// powering on a keyboard and mouse together does not produce a queue of blips.
    private var pendingConnects: [BluetoothDeviceInfo] = []
    private var pendingDisconnects: [BluetoothDeviceInfo] = []
    private var coalesceTask: Task<Void, Never>?

    private static let coalesceWindow: Duration = .milliseconds(600)

    private let bridge = NotificationBridge()

    /// IOBluetooth's callbacks are `@objc` selector based, so they need an `NSObject` to
    /// target. Keeping that separate from the manager avoids making the whole manager an
    /// `NSObject` subclass just to satisfy the C-era API.
    private final class NotificationBridge: NSObject {
        var onConnect: ((IOBluetoothDevice) -> Void)?
        var onDisconnect: ((IOBluetoothDevice) -> Void)?

        @objc func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
            onConnect?(device)
        }

        @objc func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
            // A per-device disconnect notification fires once and is then spent.
            notification.unregister()
            onDisconnect?(device)
        }
    }

    nonisolated private init() {}

    func start() {
        guard connectNotification == nil else { return }

        bridge.onConnect = { [weak self] device in
            Task { @MainActor in self?.handleConnect(device) }
        }
        bridge.onDisconnect = { [weak self] device in
            Task { @MainActor in self?.handleDisconnect(device) }
        }

        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: bridge,
            selector: #selector(NotificationBridge.deviceConnected(_:device:))
        )

        // Seed from what is already connected, so devices paired before launch do not
        // announce themselves as new the first time they emit a notification.
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
            guard device.isConnected() else { continue }
            connectedAddresses.insert(device.addressString)
            observeDisconnect(of: device)
        }
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        coalesceTask?.cancel()
        coalesceTask = nil
        connectedAddresses.removeAll()
    }

    // MARK: - Events

    private func handleConnect(_ device: IOBluetoothDevice) {
        let address = device.addressString ?? ""
        guard !address.isEmpty else { return }

        // Only a genuine transition is interesting; a device that is merely still
        // connected must not re-trigger the activity.
        guard !connectedAddresses.contains(address) else { return }
        connectedAddresses.insert(address)

        observeDisconnect(of: device)

        guard Defaults[.bluetoothConnectActivity] else { return }

        // Re-read the name every time so renames are picked up.
        let info = BluetoothDeviceInfo(address: address, name: displayName(for: device))
        pendingConnects.append(info)
        scheduleCoalescedPresentation()
    }

    private func handleDisconnect(_ device: IOBluetoothDevice) {
        let address = device.addressString ?? ""
        guard !address.isEmpty else { return }
        guard connectedAddresses.remove(address) != nil else { return }

        disconnectNotifications.removeValue(forKey: address)

        guard Defaults[.bluetoothDisconnectActivity] else { return }

        pendingDisconnects.append(
            BluetoothDeviceInfo(address: address, name: displayName(for: device))
        )
        scheduleCoalescedPresentation()
    }

    private func observeDisconnect(of device: IOBluetoothDevice) {
        let address = device.addressString ?? ""
        guard !address.isEmpty, disconnectNotifications[address] == nil else { return }

        if let notification = device.register(
            forDisconnectNotification: bridge,
            selector: #selector(NotificationBridge.deviceDisconnected(_:device:))
        ) {
            disconnectNotifications[address] = notification
        }
    }

    private func displayName(for device: IOBluetoothDevice) -> String {
        if let name = device.name, !name.isEmpty { return name }
        return device.nameOrAddress ?? device.addressString ?? "Bluetooth Device"
    }

    // MARK: - Presentation

    private func scheduleCoalescedPresentation() {
        coalesceTask?.cancel()
        coalesceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.coalesceWindow)
            guard !Task.isCancelled else { return }
            await self?.presentPending()
        }
    }

    private func presentPending() async {
        // Disconnections are rarer and more surprising, so they win a mixed batch.
        let disconnects = pendingDisconnects
        let connects = pendingConnects
        pendingDisconnects.removeAll()
        pendingConnects.removeAll()

        var devices = disconnects.isEmpty ? connects : disconnects
        guard !devices.isEmpty else { return }

        isDisconnection = !disconnects.isEmpty

        // Battery only makes sense for something still connected.
        if !isDisconnection, Defaults[.bluetoothDeviceBattery], devices.count == 1 {
            devices[0].battery = await BluetoothBatteryProvider.shared.battery(
                forAddress: devices[0].address
            )
        }

        NSLog(
            "🎧 Bluetooth \(isDisconnection ? "disconnected" : "connected"): "
                + devices.map(\.name).joined(separator: ", ")
                + (devices.first?.battery == nil ? " (no battery data)" : "")
        )

        activeDevices = devices
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .bluetooth)
    }
}
