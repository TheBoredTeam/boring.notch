//
//  SystemMetricsService.swift
//  boringNotch
//
//  Lightweight CPU / memory sampling via Mach host APIs (no subprocesses).
//

import Darwin
import Foundation

struct SystemMetrics: Equatable {
    var cpu: Double = 0       // 0...1
    var memory: Double = 0    // 0...1
}

final class SystemMetricsService {
    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    func sample() -> SystemMetrics {
        SystemMetrics(cpu: sampleCPU(), memory: sampleMemory())
    }

    private func sampleCPU() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let t = info.cpu_ticks
        let current = (user: t.0, system: t.1, idle: t.2, nice: t.3)
        defer { previousTicks = current }
        guard let p = previousTicks else { return 0 }

        let user = Double(current.user &- p.user)
        let system = Double(current.system &- p.system)
        let idle = Double(current.idle &- p.idle)
        let nice = Double(current.nice &- p.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return (user + system + nice) / total
    }

    private func sampleMemory() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = UInt64(getpagesize())
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return 0 }
        return min(1, Double(used) / Double(total))
    }
}
