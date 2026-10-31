import Foundation
import SwiftUI
import Darwin

@MainActor
final class MemoryManager: ObservableObject {
    static let shared = MemoryManager()

    @Published var usedPercent: Double = 0         // 0.0–1.0
    @Published var wiredBytes: UInt64 = 0
    @Published var activeBytes: UInt64 = 0
    @Published var compressedBytes: UInt64 = 0
    @Published var freeBytes: UInt64 = 0
    @Published var totalBytes: UInt64 = 0
    @Published var pressureLevel: MemoryPressure = .normal
    @Published var history: [Double] = []          // last 60 usedPercent samples

    private var timer: Timer?
    private var pressureSource: DispatchSourceMemoryPressure?

    private init() {
        totalBytes = ProcessInfo.processInfo.physicalMemory
        setupPressureSource()
        startPolling()
    }

    private func setupPressureSource() {
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let event = src.data
            if event.contains(.critical) { self.pressureLevel = .critical }
            else if event.contains(.warning) { self.pressureLevel = .warning }
            else { self.pressureLevel = .normal }
        }
        src.resume()
        pressureSource = src
    }

    private func startPolling() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    private func refresh() {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let page = UInt64(vm_kernel_page_size)
        wiredBytes      = UInt64(stats.wire_count)      * page
        activeBytes     = UInt64(stats.active_count)    * page
        compressedBytes = UInt64(stats.compressor_page_count) * page
        freeBytes       = UInt64(stats.free_count)      * page

        let used = wiredBytes + activeBytes + compressedBytes
        usedPercent = totalBytes > 0 ? Double(used) / Double(totalBytes) : 0

        history.append(usedPercent)
        if history.count > 60 { history.removeFirst() }
    }
}

enum MemoryPressure {
    case normal, warning, critical
    var color: Color {
        switch self {
        case .normal:   return Color(red: 0.4, green: 0.85, blue: 0.6)
        case .warning:  return Color(red: 1.0, green: 0.75, blue: 0.3)
        case .critical: return Color(red: 1.0, green: 0.35, blue: 0.35)
        }
    }
    var label: String {
        switch self {
        case .normal:   return "Normal"
        case .warning:  return "Warning"
        case .critical: return "Critical"
        }
    }
}
