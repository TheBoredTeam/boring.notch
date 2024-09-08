    //
    //  BoringViewModel.swift
    //  boringNotch
    //
    //  Created by Harsh Vardhan  Goswami  on 04/08/24.
    //


import Cocoa
import SwiftUI
import IOKit.ps

class BatteryStatusViewModel: ObservableObject {
    private var vm: BoringViewModel
    @Published var batteryPercentage: Float = 0.0
    @Published var isPluggedIn: Bool = false
    @Published var showChargingInfo: Bool = false
    
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?
    var animations: BoringAnimations = BoringAnimations()
    
    init(vm: BoringViewModel) {
        self.vm = vm
        updateBatteryStatus()
        startMonitoring()
    }
    
    private func updateBatteryStatus() {
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: AnyObject],
                   let currentCapacity = info[kIOPSCurrentCapacityKey] as? Int,
                   let maxCapacity = info[kIOPSMaxCapacityKey] as? Int,
                   let isCharging = info["Is Charging"] as? Bool {
                    
                    
                    if(self.vm.chargingInfoAllowed) {
                        
                        withAnimation {
                            self.batteryPercentage = Float((currentCapacity * 100) / maxCapacity)
                        }
                        
                        if (isCharging && !self.isPluggedIn) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + (vm.firstLaunch ? 6 : 0)) {
                                self.vm.toggleExpandingView(status: true, type: .battery)
                                self.showChargingInfo = true
                                self.isPluggedIn = true
                            }
                            
                        }
                        withAnimation {
                            self.isPluggedIn = isCharging
                        }
                        
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
    
    deinit {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource.takeUnretainedValue(), .defaultMode)
            runLoopSource.release()
        }
    }
}
