import Cocoa
import Defaults
import Foundation
import IOKit.ps
import SwiftUI

/// A view model that manages and monitors the battery status of the device.
class BatteryStatusViewModel: ObservableObject {

    /// Callback for power source changes.
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    /// Run loop source for battery monitoring.
    private var runLoopSource: Unmanaged<CFRunLoopSource>?
    /// Animations handler for UI updates.
    var animations: BoringAnimations = BoringAnimations()

    /// Shared coordinator for view updates.
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    /// Current battery level (0.0 - 100.0).
    @Published private(set) var levelBattery: Float = 0.0
    /// Maximum battery capacity.
    @Published private(set) var maxCapacity: Float = 0.0
    /// Indicates if the device is plugged in.
    @Published private(set) var isPluggedIn: Bool = false
    /// Indicates if the device is charging.
    @Published private(set) var isCharging: Bool = false
    /// Indicates if low power mode is enabled.
    @Published private(set) var isInLowPowerMode: Bool = false
    /// Indicates if the initial battery info has been loaded.
    @Published private(set) var isInitial: Bool = false
    /// Estimated time to full charge (in minutes).
    @Published private(set) var timeToFullCharge: Int = 0
    /// Textual status of the battery, often with emojis.
    @Published private(set) var statusText: String = ""

    /// Shared battery manager instance.
    private let managerBattery = BatteryActivityManager.shared
    /// Observer ID for battery manager events.
    private var managerBatteryId: Int?

    /// Singleton instance of the view model.
    static let shared = BatteryStatusViewModel()

    /// Initializes the view model and sets up battery monitoring.
    private init() {
        setupPowerStatus()
        setupMonitor()
    }

    /// Fetches initial battery information and updates properties.
    private func setupPowerStatus() {
        let batteryInfo = managerBattery.initializeBatteryInfo()
        updateBatteryInfo(batteryInfo)
    }

    /// Registers observer for battery events.
    private func setupMonitor() {
        managerBatteryId = managerBattery.addObserver { [weak self] event in
            guard let self = self else { return }
            self.handleBatteryEvent(event)
        }
    }

    /// Handles battery events and updates published properties.
    /// - Parameter event: The battery event to process.
    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {
        case .powerSourceChanged(let isPluggedIn):
            print("🔌 Power source: \(isPluggedIn ? "Connected" : "Disconnected")")
            withAnimation {
                self.isPluggedIn = isPluggedIn
                self.statusText = isPluggedIn ? "Plugged In" : "Unplugged"
                self.notifyImportanChangeStatus()
            }

        case .batteryLevelChanged(let level):
            print("🔋 Battery level: \(Int(level))%")
            let lowThreshold = Float(Defaults[.lowBatteryNotificationLevel])
            let highThreshold = Float(Defaults[.highBatteryNotificationLevel])
            var text = ""

            if !isCharging && level == lowThreshold {
                notifyImportanChangeStatus()
                text = "Low Battery"
            } else if isCharging && level == highThreshold {
                notifyImportanChangeStatus()
                text = "High Battery"
            }

            withAnimation {
                statusText = text
                levelBattery = level
            }

        case .lowPowerModeChanged(let isEnabled):
            print("⚡ Low power mode: \(isEnabled ? "Enabled" : "Disabled")")
            self.notifyImportanChangeStatus()
            withAnimation {
                self.isInLowPowerMode = isEnabled
                self.statusText = "Low Power: \(self.isInLowPowerMode ? "On" : "Off")"
            }

        case .isChargingChanged(let isCharging):
            print("🔌 Charging: \(isCharging ? "Yes" : "No")")
            print("maxCapacity: \(self.maxCapacity)")
            print("levelBattery: \(self.levelBattery)")
            self.notifyImportanChangeStatus()
            withAnimation {
                self.isCharging = isCharging
                self.statusText =
                    isCharging
                    ? "Charging"
                    : (self.levelBattery < self.maxCapacity ? "Not Charging" : "Full Charge")
            }

        case .timeToFullChargeChanged(let time):
            print("🕒 Time to full charge: \(time) minutes")
            withAnimation {
                self.timeToFullCharge = time
            }

        case .maxCapacityChanged(let capacity):
            print("🔋 Max capacity: \(capacity)")
            withAnimation {
                self.maxCapacity = capacity
            }

        case .error(let description):
            print("⚠️ Error: \(description)")
        }
    }

    /// Updates all battery properties from a BatteryInfo instance.
    /// - Parameter batteryInfo: The battery information to apply.
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

    /// Notifies the coordinator about important battery status changes.
    /// - Parameter delay: Optional delay before notification (default: 0.0 seconds).
    private func notifyImportanChangeStatus(delay: Double = 0.0) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            self.coordinator.toggleExpandingView(status: true, type: .battery)
        }
    }

    /// Cleans up battery monitoring observers on deinitialization.
    deinit {
        print("🔌 Cleaning up battery monitoring...")
        if let managerBatteryId: Int = managerBatteryId {
            managerBattery.removeObserver(byId: managerBatteryId)
        }
    }

}
