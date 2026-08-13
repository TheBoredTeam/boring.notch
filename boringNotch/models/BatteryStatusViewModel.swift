import Cocoa
import Defaults
import Foundation
import IOKit.ps
import SwiftUI

/// A view model that manages and monitors the battery status of the device
class BatteryStatusViewModel: ObservableObject {

    private var wasCharging: Bool = false
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?

    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Published private(set) var levelBattery: Float = 0.0
    @Published private(set) var maxCapacity: Float = 0.0
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isInLowPowerMode: Bool = false
    @Published private(set) var isInitial: Bool = false
    @Published private(set) var timeToFullCharge: Int = 0
    @Published private(set) var statusText: String = ""

    private let managerBattery = BatteryActivityManager.shared
    private var managerBatteryId: Int?

    static let shared = BatteryStatusViewModel()

    /// Initializes the view model with a given BoringViewModel instance
    /// - Parameter vm: The BoringViewModel instance
    private init() {
        setupPowerStatus()
        setupMonitor()
    }

    /// Sets up the initial power status by fetching battery information
    private func setupPowerStatus() {
        let batteryInfo = managerBattery.initializeBatteryInfo()
        updateBatteryInfo(batteryInfo)
    }

    /// Sets up the monitor to observe battery events
    private func setupMonitor() {
        managerBatteryId = managerBattery.addObserver { [weak self] event in
            guard let self = self else { return }
            self.handleBatteryEvent(event)
        }
    }

    /// Handles battery events and updates the corresponding properties
    /// - Parameter event: The battery event to handle
    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {
        case .powerSourceChanged(let isPluggedIn):
            withAnimation {
                self.isPluggedIn = isPluggedIn
                self.statusText = isPluggedIn ? "Plugged In" : "Unplugged"
                self.notifyImportanChangeStatus()
            }

        case .batteryLevelChanged(let level):
            withAnimation {
                self.levelBattery = level
            }

        case .lowPowerModeChanged(let isEnabled):
            self.notifyImportanChangeStatus()
            withAnimation {
                self.isInLowPowerMode = isEnabled
                self.statusText = "Low Power: \(self.isInLowPowerMode ? "On" : "Off")"
            }

        case .isChargingChanged(let isCharging):
            self.notifyImportanChangeStatus()
            withAnimation {
                self.isCharging = isCharging
                self.statusText =
                    isCharging
                    ? "Charging battery"
                    : (self.levelBattery < self.maxCapacity ? "Not charging" : "Full charge")
            }

        case .timeToFullChargeChanged(let time):
            withAnimation {
                self.timeToFullCharge = time
            }

        case .maxCapacityChanged(let capacity):
            withAnimation {
                self.maxCapacity = capacity
            }

        case .error:
            break
        }
    }

    /// Updates the battery information with the given BatteryInfo instance
    /// - Parameter batteryInfo: The BatteryInfo instance containing the battery data
    private func updateBatteryInfo(_ batteryInfo: BatteryInfo) {
        withAnimation {
            self.levelBattery = batteryInfo.currentCapacity
            self.isPluggedIn = batteryInfo.isPluggedIn
            self.isCharging = batteryInfo.isCharging
            self.isInLowPowerMode = batteryInfo.isInLowPowerMode
            self.timeToFullCharge = batteryInfo.timeToFullCharge
            self.maxCapacity = batteryInfo.maxCapacity
            self.statusText = batteryInfo.isPluggedIn ? "Plugged In" : "Unplugged"
        }
    }

    /// Notifies important changes in the battery status with an optional delay
    /// - Parameter delay: The delay before notifying the change, default is 0.0
    private func notifyImportanChangeStatus(delay: Double = 0.0) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            self.coordinator.toggleExpandingView(status: true, type: .battery)
        }
    }

    deinit {
        if let managerBatteryId: Int = managerBatteryId {
            managerBattery.removeObserver(byId: managerBatteryId)
        }
    }

}

struct BluetoothAccessoryBatteryPart: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case left
        case right
        case chargingCase = "case"
        case main
        case combined

        var shortLabel: String {
            switch self {
            case .left: return "L"
            case .right: return "R"
            case .chargingCase: return "C"
            case .main, .combined: return ""
            }
        }
    }

    let kind: Kind
    let percentage: Int
    let isCharging: Bool

    var id: Kind { kind }
}

struct BluetoothAccessoryBatteryDevice: Codable, Hashable, Identifiable {
    let name: String
    let category: String
    let parts: [BluetoothAccessoryBatteryPart]

    var id: String {
        "\(category.lowercased()):\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    var systemImage: String {
        switch category {
        case "headphones": return "airpodspro"
        case "keyboard": return "keyboard"
        case "trackpad": return "rectangle.and.hand.point.up.left"
        case "mouse": return "computermouse"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}

struct KnownBluetoothAccessory: Codable, Hashable, Identifiable, Defaults.Serializable {
    let id: String
    let name: String
    let category: String

    init(device: BluetoothAccessoryBatteryDevice) {
        id = device.id
        name = device.name
        category = device.category
    }

    var systemImage: String {
        switch category {
        case "headphones": return "airpodspro"
        case "keyboard": return "keyboard"
        case "trackpad": return "rectangle.and.hand.point.up.left"
        case "mouse": return "computermouse"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}

@MainActor
final class BluetoothAccessoryBatteryManager: ObservableObject {
    static let shared = BluetoothAccessoryBatteryManager()

    @Published private(set) var devices: [BluetoothAccessoryBatteryDevice] = []
    @Published private(set) var knownDevices: [KnownBluetoothAccessory]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private var lastRefreshDate: Date?
    private var refreshLoop: Task<Void, Never>?

    private init() {
        knownDevices = Defaults[.knownBluetoothAccessories]
    }

    func startMonitoring() {
        guard refreshLoop == nil else { return }
        refreshLoop = Task { @MainActor [weak self] in
            guard let self else { return }
            await refresh(force: false)

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(120))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await refresh(force: true)
            }
        }
    }

    func stopMonitoring() {
        refreshLoop?.cancel()
        refreshLoop = nil
    }

    func refresh(force: Bool = false) async {
        if !force,
           let lastRefreshDate,
           Date().timeIntervalSince(lastRefreshDate) < 20
        {
            return
        }
        guard !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        guard let data = await XPCHelperClient.shared.bluetoothAccessoryBatteryData() else {
            lastError = "设备电量暂时不可用"
            return
        }

        do {
            devices = try JSONDecoder().decode([BluetoothAccessoryBatteryDevice].self, from: data)
            remember(devices)
            lastRefreshDate = Date()
            lastError = nil
        } catch {
            lastError = "无法读取设备电量"
        }
    }

    private func remember(_ devices: [BluetoothAccessoryBatteryDevice]) {
        guard !devices.isEmpty else { return }

        var rememberedByID: [String: KnownBluetoothAccessory] = [:]
        for device in knownDevices {
            rememberedByID[device.id] = device
        }
        for device in devices {
            rememberedByID[device.id] = KnownBluetoothAccessory(device: device)
        }
        let updated = rememberedByID.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        guard updated != knownDevices else { return }
        knownDevices = updated
        Defaults[.knownBluetoothAccessories] = updated
    }
}
