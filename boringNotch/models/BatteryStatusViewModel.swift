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
            self.notifyImportanChangeStatus(sound: Defaults[.powerStatusNotificationSound])
            withAnimation {
                self.isPluggedIn = isPluggedIn
                self.statusText = isPluggedIn ? "Plugged In" : "Unplugged"
            }

        case .batteryLevelChanged(let level):
            print("🔋 Battery level: \(Int(level))%")
            withAnimation {
                self.levelBattery = level
            }
            self.batteryLevelNotification(level: Int(level))

        case .lowPowerModeChanged(let isEnabled):
            print("⚡ Low power mode: \(isEnabled ? "Enabled" : "Disabled")")
            self.notifyImportanChangeStatus(sound: Defaults[.powerStatusNotificationSound])
            withAnimation {
                self.isInLowPowerMode = isEnabled
                self.statusText = "Low Power: \(self.isInLowPowerMode ? "On" : "Off")"
            }

        case .isChargingChanged(let isCharging):
            print("🔌 Charging: \(isCharging ? "Yes" : "No")")
            print("maxCapacity: \(self.maxCapacity)")
            print("levelBattery: \(self.levelBattery)")
            self.notifyImportanChangeStatus(sound: Defaults[.powerStatusNotificationSound])
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
        self.notifyImportanChangeStatus(sound: Defaults[.powerStatusNotificationSound])
        withAnimation {
            self.levelBattery = batteryInfo.currentCapacity
            self.isPluggedIn = batteryInfo.isPluggedIn
            self.isCharging = batteryInfo.isCharging
            self.isInLowPowerMode = batteryInfo.isInLowPowerMode
            self.timeToFullCharge = batteryInfo.timeToFullCharge
            self.maxCapacity = batteryInfo.maxCapacity
            self.statusText = batteryInfo.isPluggedIn ? "Plugged In" : "Unplugged"
        }
        Task {
            try? await Task.sleep(for: .seconds(2.0))
            self.batteryLevelNotification(level: Int(self.levelBattery), initial: true)
        }
    }

    private func batteryLevelNotification(level: Int, initial: Bool = false) {
        guard let text = notificationText(for: level, initial: initial) else { return }
        
        let sound = text == "Low Battery"
            ? Defaults[.lowBatteryNotificationSound]
            : Defaults[.highBatteryNotificationSound]
            
        self.notifyImportanChangeStatus(sound: sound)
        withAnimation {
            self.statusText = text
        }
    }
    
    private func notificationText(for level: Int, initial: Bool) -> String? {
        let lowThreshold = Defaults[.lowBatteryNotificationLevel]
        let highThreshold = Defaults[.highBatteryNotificationLevel]
        
        if !self.isCharging && (level == lowThreshold || (initial && level <= lowThreshold)) {
            return "Low Battery"
        }
        if self.isCharging && (level == highThreshold || (initial && level >= highThreshold)) {
            return "High Battery"
        }
        return nil
    }
    
    /// Notifies the coordinator about important battery status changes.
    private func notifyImportanChangeStatus(sound: String) {
        self.coordinator.toggleExpandingView(status: true, type: .battery)
        if sound != "Disabled" {
            NSSound(named: NSSound.Name(sound))?.play()
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
