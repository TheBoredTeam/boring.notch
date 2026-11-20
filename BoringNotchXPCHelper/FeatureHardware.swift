// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import IOBluetooth
import ApplicationServices

final class FeatureHardware: NSObject {
    var onEvent: ((Data) -> Void)?
    private var connectToken: IOBluetoothUserNotification?
    private var disconnectTokens: [IOBluetoothUserNotification] = []
    private var state = FeatureBridgeState()
    private var settle: DispatchWorkItem?
    deinit { connectToken?.unregister(); disconnectTokens.forEach { $0.unregister() } }
    func configure(bluetooth: Bool, notifications: Bool) -> Data {
        if bluetooth {
            if connectToken == nil { connectToken = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceChanged(_:device:))) }
            updateDevices()
            state.bluetoothRunning = connectToken != nil
        } else {
            connectToken?.unregister(); connectToken = nil
            disconnectTokens.forEach { $0.unregister() }; disconnectTokens = []
            state.devices = []; state.bluetoothRunning = false
        }
        return (try? JSONEncoder().encode(FeatureBridgeEvent(kind: "state", state: state))) ?? Data()
    }
    @objc private func deviceChanged(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connectToken != nil else { return }
            self.updateDevices(); self.send(.init(kind: "state", state: self.state))
        }
        settle = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    private func updateDevices() {
        disconnectTokens.forEach { $0.unregister() }; disconnectTokens = []
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        state.devices = devices.compactMap { device in
            guard let address = device.addressString else { return nil }
            if device.isConnected(), let token = device.register(forDisconnectNotification: self, selector: #selector(deviceChanged(_:device:))) { disconnectTokens.append(token) }
          return FeatureDevice(id: address, name: device.name ?? "Bluetooth device", connected: device.isConnected())
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private func send(_ event: FeatureBridgeEvent) { if let data = try? JSONEncoder().encode(event) { onEvent?(data) } }
}
