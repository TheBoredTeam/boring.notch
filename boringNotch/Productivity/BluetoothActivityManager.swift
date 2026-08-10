import Defaults
import Foundation
@preconcurrency import IOBluetooth

@MainActor
final class BluetoothActivityManager: ObservableObject {
    static let shared = BluetoothActivityManager()

    @Published private(set) var connectedDevices: [BluetoothDeviceSnapshot] = []
    @Published private(set) var lastChangedDevice: BluetoothDeviceSnapshot?

    private var monitoringTask: Task<Void, Never>?
    private var hasCompletedInitialScan = false

    private init() {
        if Defaults[.bluetoothLiveActivityEnabled] {
            startMonitoring()
        }
    }

    deinit {
        monitoringTask?.cancel()
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        connectedDevices = []
        lastChangedDevice = nil
        hasCompletedInitialScan = false
    }

    func refreshConfiguration() {
        Defaults[.bluetoothLiveActivityEnabled] ? startMonitoring() : stopMonitoring()
    }

    func refresh() {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let snapshots = paired.compactMap { device -> BluetoothDeviceSnapshot? in
            guard device.isConnected() else { return nil }
            let name = device.name ?? "Bluetooth Device"
            let identifier = device.addressString ?? name
            return BluetoothDeviceSnapshot(
                id: identifier,
                name: name,
                isConnected: true,
                isAirPods: Self.looksLikeAirPods(name)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isAirPods != rhs.isAirPods { return lhs.isAirPods }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let oldByID = Dictionary(uniqueKeysWithValues: connectedDevices.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })

        if hasCompletedInitialScan {
            if let connected = snapshots.first(where: { oldByID[$0.id] == nil }) {
                lastChangedDevice = connected
                BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .bluetooth)
            } else if let disconnected = connectedDevices.first(where: { newByID[$0.id] == nil }) {
                lastChangedDevice = BluetoothDeviceSnapshot(
                    id: disconnected.id,
                    name: disconnected.name,
                    isConnected: false,
                    isAirPods: disconnected.isAirPods
                )
                BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .bluetooth)
            }
        }

        connectedDevices = snapshots
        hasCompletedInitialScan = true
    }

    private static func looksLikeAirPods(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.contains("airpods") || normalized.contains("beats")
    }
}
