//
//  Battery.swift
//  boringNotch
//
//  Created by Gokul on 18/08/24.
//

import IOKit.ps

func hasBattery() -> Bool {
    let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
    for ps in sources {
        if let powerSource = IOPSGetPowerSourceDescription(snapshot, ps).takeUnretainedValue() as? [String: Any] {
            if let type = powerSource[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                return true
            }
        }
    }
    return false
}
