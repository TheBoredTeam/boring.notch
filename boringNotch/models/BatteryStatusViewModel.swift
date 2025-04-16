import Foundation
import Cocoa
import SwiftUI
import IOKit.ps
import Defaults

/// A view model that manages and monitors the battery status of the device
class BatteryStatusViewModel: ObservableObject {
    
    private var wasCharging: Bool = false
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?
    var animations: BoringAnimations = BoringAnimations()

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
    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent)  {
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
                    withAnimation {
                        self.levelBattery = level
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
                        self.statusText = isCharging ? "Charging battery" : (self.levelBattery < self.maxCapacity ? "Not charging" : "Full charge")
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
        notifyImportanChangeStatus(delay: coordinator.firstLaunch ? 6 : 0.0)
        withAnimation {
            if self.isCharging {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.statusText = "Charging: Yes"
                }
            }
            if self.isInLowPowerMode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.statusText = "Low Power: On"
                }
            }
        }
    }
    
    /// Notifies important changes in the battery status with an optional delay
    /// - Parameter delay: The delay before notifying the change, default is 0.0
    private func notifyImportanChangeStatus(delay: Double = 0.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.coordinator.toggleExpandingView(status: true, type: .battery)
        }
    }

    deinit {
        print("🔌 Cleaning up battery monitoring...")
        if let managerBatteryId: Int = managerBatteryId {
            managerBattery.removeObserver(byId: managerBatteryId)
        }
    }
    
}
