//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Cocoa
import SwiftUI
import IOKit.ps
import Defaults

/// A view model that manages and monitors the battery status of the device
class BatteryStatusViewModel: ObservableObject {
    
    private var wasCharging: Bool = false
    private var vm: BoringViewModel
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?
    var animations: BoringAnimations = BoringAnimations()

    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Published private(set) var batteryPercentage: Float = 0.0
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var showChargingInfo: Bool = false
    @Published private(set) var isInLowPowerMode: Bool = false
    @Published private(set) var isInitialPlugIn: Bool = true
    @Published private(set) var isUnplugged: Bool = false
    @Published private(set) var timeRemaining: Int? = nil
    @Published private(set) var statusText: String = ""

    init(vm: BoringViewModel) {
        self.vm = vm
        setupInitialState()
    }
    
    // MARK: - Setup Methods
    
    /// Initializes the battery monitoring system
    private func setupInitialState(){
        updateBatteryStatus()
        startMonitoring()
        setupPowerModeObserver()
    }
    
    
    /// Sets up observer for system power mode changes
    private func setupPowerModeObserver() {
        isInLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    // MARK: - Battery Status Methods

    /// Updates the battery status and UI based on current power source state
    private func updateBatteryStatus() {
        guard let info = getBatteryInfo() else { return }
        self.timeRemaining = getTimeRemaining()
        let delay: Double = coordinator.firstLaunch ? 6 : 0
        
        var status: BatteryStatus = .unplugged
        var isInitialPlugIn: Bool = true
        var isUnplugged: Bool = false
        
        if (info.isACPower && !self.isPluggedIn){
            status = .pluggedIn
            isInitialPlugIn = true
        }
        
        if (!info.isACPower && self.isPluggedIn){
            status = .unplugged
            isUnplugged = true
        }
        
        if (info.isCharging && !self.wasCharging && info.isACPower) {
            status = .charging
        }
        
        updateUIPowerStatus(
            delay: delay,
            status: status,
            isInitialPlugIn: isInitialPlugIn,
            isUnplugged: isUnplugged,
            isACPower: info.isACPower,
            isCharging: info.isCharging,
            currentCapacity: info.currentCapacity,
            maxCapacity: info.maxCapacity
        )
        
    }
    
    /// Updates the UI with current battery and power status
    /// - Parameters:
    ///   - delay: Time to wait before updating UI
    ///   - status: Current battery status
    ///   - isInitialPlugIn: Whether this is the first plug-in event
    ///   - isUnplugged: Whether the device was just unplugged
    ///   - isACPower: Whether the device is connected to power
    ///   - isCharging: Whether the battery is charging
    ///   - currentCapacity: Current battery capacity
    ///   - maxCapacity: Maximum battery capacity
    private func updateUIPowerStatus(
        delay: Double,
        status: BatteryStatus,
        isInitialPlugIn: Bool = false,
        isUnplugged: Bool = false,
        isACPower: Bool = false,
        isCharging: Bool = false,
        currentCapacity: Int = 0,
        maxCapacity: Int = 0
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation {
                self.batteryPercentage = Float((currentCapacity * 100) / maxCapacity)
                self.vm.toggleExpandingView(status: true, type: .battery)
                self.showChargingInfo = true
                self.isInitialPlugIn = isInitialPlugIn
                self.isUnplugged = isUnplugged
                self.isPluggedIn = isACPower
                self.statusText = status.rawValue
                self.wasCharging = isCharging
            }
        }
    }
    
    /// Updates the UI when low power mode status changes
    private func updateLowPowerModeStatus(){
        guard let info = getBatteryInfo() else { return }
        withAnimation {
            self.batteryPercentage = Float((info.currentCapacity * 100) / info.maxCapacity)
            self.vm.toggleExpandingView(status: true, type: .battery)
            self.showChargingInfo = true
            self.isPluggedIn = info.isACPower
            self.statusText = "Low Power: \(self.isInLowPowerMode ? "On" : "Off")"
            self.wasCharging = info.isCharging
        }
    }
    
    // MARK: - Battery Information Methods

    /// Retrieves current battery information from the system
    /// - Returns: A BatteryInfo object containing current battery state or nil if information cannot be retrieved
    private func getBatteryInfo() -> BatteryInfo? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: AnyObject],
              let currentCapacity = info[kIOPSCurrentCapacityKey] as? Int,
              let maxCapacity = info[kIOPSMaxCapacityKey] as? Int,
              let isCharging = info["Is Charging"] as? Bool,
              let powerSource = info[kIOPSPowerSourceStateKey] as? String else {
            return nil
        }
        
        return BatteryInfo(
            currentCapacity: currentCapacity,
            maxCapacity: maxCapacity,
            isCharging: isCharging,
            isACPower: powerSource == "AC Power",
            info: info
        )
    }
    
    /// Calculates remaining battery time
    /// - Returns: Time remaining in minutes, or nil if unavailable
    private func getTimeRemaining() -> Int? {
        guard let info = getBatteryInfo() else { return nil }
        
        if info.isACPower && info.isCharging {
            return (info.info[kIOPSTimeToFullChargeKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
        } else if !info.isACPower {
            return (info.info[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
        }
        return nil
    }

    // MARK: - Monitoring Methods

    /// Starts monitoring battery status changes
    private func startMonitoring() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        powerSourceChangedCallback = { context in
            guard let context = context else { return }
            let instance = Unmanaged<BatteryStatusViewModel>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                instance.updateBatteryStatus()
            }
        }

        if let runLoopSource = IOPSNotificationCreateRunLoopSource(powerSourceChangedCallback!, context)?.takeRetainedValue() {
            self.runLoopSource = Unmanaged<CFRunLoopSource>.passRetained(runLoopSource)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        }
    }
    
    /// Handles power state change notifications
    /// - Parameter notification: System notification about power state change
    @objc func powerStateChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isInLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            self.updateLowPowerModeStatus()
        }
    }
    
    /// Cleans up run loop source when view model is deallocated
    private func cleanupRunLoopSource() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource.takeUnretainedValue(), .defaultMode)
            runLoopSource.release()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanupRunLoopSource()
    }
    
}


/// Represents different battery connection states
private enum BatteryStatus: String {
    case pluggedIn = "Plugged In"
    case unplugged = "Unplugged"
    case charging = "Charging"
}

/// Contains information about the battery's current state
private struct BatteryInfo {
    let currentCapacity: Int
    let maxCapacity: Int
    let isCharging: Bool
    let isACPower: Bool
    let info: [String: AnyObject]
}
