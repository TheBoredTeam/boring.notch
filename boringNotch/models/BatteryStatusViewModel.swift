import Cocoa
import SwiftUI
import IOKit.ps

class BatteryStatusViewModel: ObservableObject {
    @Published var batteryPercentage: Float = 0.0
    @Published var isPluggedIn: Bool = false
    @Published var showChargingInfo: Bool = false
    
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?

    
    init() {
        updateBatteryStatus()
        startMonitoring()
    }

    private func updateBatteryStatus() {
        print("updateBatteryStatus")
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: AnyObject],
                   let currentCapacity = info[kIOPSCurrentCapacityKey] as? Int,
                   let maxCapacity = info[kIOPSMaxCapacityKey] as? Int,
                   let isCharging = info["Is Charging"] as? Bool {
                    self.batteryPercentage = Float((currentCapacity * 100) / maxCapacity)
                    
                    if (isCharging && !self.isPluggedIn) {
                        
                        self.showChargingInfo = true
                        self.isPluggedIn = true
                         DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                             self.showChargingInfo = false
                         }
                    }
                    
                    print(self.isPluggedIn, isCharging)
                    
                    self.isPluggedIn = isCharging
                    
                    
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
