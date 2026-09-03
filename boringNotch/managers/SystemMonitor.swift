import Foundation
import MachO

final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published var cpuUsage: Double = 0
    @Published var memoryPressure: Double = 0
    @Published var memoryUsed: UInt64 = 0
    @Published var memoryTotal: UInt64 = 0

    private var timer: Timer?
    private var previousCPUInfo: host_cpu_load_info?

    private init() {
        memoryTotal = ProcessInfo.processInfo.physicalMemory
        previousCPUInfo = cpuLoadInfo()
    }

    func start() {
        guard timer == nil else { return }
        updateStats()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func updateStats() {
        updateCPU()
        updateMemory()
    }

    private func updateCPU() {
        guard let current = cpuLoadInfo(), let previous = previousCPUInfo else { return }
        previousCPUInfo = current

        let user = UInt64(current.cpu_ticks.0 &- previous.cpu_ticks.0)
        let system = UInt64(current.cpu_ticks.1 &- previous.cpu_ticks.1)
        let idle = UInt64(current.cpu_ticks.2 &- previous.cpu_ticks.2)
        let nice = UInt64(current.cpu_ticks.3 &- previous.cpu_ticks.3)

        let total = user &+ system &+ idle &+ nice
        guard total > 0 else { return }

        let usage = Double(user &+ system &+ nice) / Double(total) * 100.0
        DispatchQueue.main.async { self.cpuUsage = usage }
    }

    private func updateMemory() {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let used = (UInt64(info.active_count) &+ UInt64(info.wire_count) &+ UInt64(info.compressor_page_count)) &* pageSize
        let pressure = memoryTotal > 0 ? Double(used) / Double(memoryTotal) * 100.0 : 0

        DispatchQueue.main.async {
            self.memoryUsed = used
            self.memoryPressure = pressure
        }
    }

    private func cpuLoadInfo() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    deinit { timer?.invalidate() }
}
