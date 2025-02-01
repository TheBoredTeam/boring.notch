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

class BatteryStatusViewModel: ObservableObject {
    private var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Published var batteryPercentage: Float = 0.0
    @Published var isPluggedIn: Bool = false
    @Published var showChargingInfo: Bool = false
    @Published var isInLowPowerMode: Bool = false
    @Published var isInitialPlugIn: Bool = true
    private var wasCharging: Bool = false

    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?
    var animations: BoringAnimations = BoringAnimations()

    init(vm: BoringViewModel) {
        self.vm = vm
        updateBatteryStatus()
        startMonitoring()
        // get the system power mode and setup an observer
        self.isInLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
    }

    private func updateBatteryStatus() {
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: AnyObject],
                   let currentCapacity = info[kIOPSCurrentCapacityKey] as? Int,
                   let maxCapacity = info[kIOPSMaxCapacityKey] as? Int,
                   let isCharging = info["Is Charging"] as? Bool,
                   let powerSource = info[kIOPSPowerSourceStateKey] as? String {
                    if(Defaults[.chargingInfoAllowed]) {
                        withAnimation {
                            self.batteryPercentage = Float((currentCapacity * 100) / maxCapacity)
                        }

                        let isACPower = powerSource == "AC Power"
                        
                        // Show "Plugged In" notification when first connected to power
                        if (isACPower && !self.isPluggedIn) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + (coordinator.firstLaunch ? 6 : 0)) {
                                self.vm.toggleExpandingView(status: true, type: .battery)
                                self.showChargingInfo = true
                                self.isPluggedIn = true
                                self.isInitialPlugIn = true
                            }
                        }
                        
                        // Show "Charging" notification when charging begins
                        if (isCharging && !self.wasCharging && isACPower) {
                            self.vm.toggleExpandingView(status: true, type: .battery)
                            self.showChargingInfo = true
                            self.isInitialPlugIn = false
                        }
                        
                        withAnimation {
                            self.isPluggedIn = isACPower
                        }
                        self.wasCharging = isCharging
                    }
                }
            }
        }
    }

    private func startMonitoring() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        powerSourceChangedCallback = { context in
            if let context = context {
                let mySelf = Unmanaged<BatteryStatusViewModel>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async {
                    mySelf.updateBatteryStatus()
                }
            }
        }

        if let runLoopSource = IOPSNotificationCreateRunLoopSource(powerSourceChangedCallback!, context)?.takeRetainedValue() {
            self.runLoopSource = Unmanaged<CFRunLoopSource>.passRetained(runLoopSource)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        }
    }
    
    // function to update battery model if system low power mode changes
    @objc func powerStateChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isInLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    deinit {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource.takeUnretainedValue(), .defaultMode)
            runLoopSource.release()
        }
    }
}
