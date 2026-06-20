//
//  CPUTemperatureReader.swift
//  boringNotch
//
//  Created by Maksymilian Wójcik on 2026-06-09.
//
//  Reads on-die temperature sensors via the private IOHIDEventSystemClient API
//  (resolved at runtime with dlsym) and averages the SoC thermal sensors
//  (usage page 0xFF00 / usage 5) as a CPU-temperature proxy. Works because the
//  app runs without the App Sandbox. Returns nil if sensors are unavailable.
//

import Foundation
import IOKit

final class CPUTemperatureReader {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias MatchFn = @convention(c) (AnyObject?, CFDictionary?) -> Int32
    private typealias ServicesFn = @convention(c) (AnyObject?) -> Unmanaged<CFArray>?
    private typealias EventFn = @convention(c) (AnyObject?, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias FloatFn = @convention(c) (AnyObject?, Int32) -> Double

    private let servicesFn: ServicesFn
    private let eventFn: EventFn
    private let floatFn: FloatFn
    private let client: AnyObject

    private let temperatureType: Int64 = 15
    private let temperatureField: Int32 = 15 << 16

    init?() {
        let handle = dlopen(nil, RTLD_LAZY)
        func load<T>(_ name: String) -> T? {
            guard let sym = dlsym(handle, name) else { return nil }
            return unsafeBitCast(sym, to: T.self)
        }
        guard let create: CreateFn = load("IOHIDEventSystemClientCreate"),
            let match: MatchFn = load("IOHIDEventSystemClientSetMatching"),
            let services: ServicesFn = load("IOHIDEventSystemClientCopyServices"),
            let event: EventFn = load("IOHIDServiceClientCopyEvent"),
            let float: FloatFn = load("IOHIDEventGetFloatValue"),
            let clientRef = create(kCFAllocatorDefault)?.takeRetainedValue()
        else { return nil }

        servicesFn = services
        eventFn = event
        floatFn = float
        client = clientRef
        _ = match(clientRef, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
    }

    /// Average of the available on-die temperature sensors (°C), or nil.
    func readAverage() -> Double? {
        guard let services = servicesFn(client)?.takeRetainedValue() as? [AnyObject],
            !services.isEmpty
        else { return nil }

        var sum = 0.0
        var count = 0
        for service in services {
            guard let event = eventFn(service, temperatureType, 0, 0)?.takeRetainedValue() else {
                continue
            }
            let value = floatFn(event, temperatureField)
            if value > 0, value < 130 {
                sum += value
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : nil
    }
}
