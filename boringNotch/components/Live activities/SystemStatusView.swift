import SwiftUI
import Defaults

/// Compact system status indicators for the closed notch (CPU, RAM, VPN)
struct SystemStatusView: View {
    @ObservedObject var systemMonitor = SystemMonitor.shared
    @ObservedObject var vpnManager = VPNManager.shared
    @Default(.showCPUUsage) var showCPU
    @Default(.showRAMUsage) var showRAM

    var body: some View {
        HStack(spacing: 10) {
            if showCPU {
                cpuIndicator
            }
            if showRAM {
                ramIndicator
            }
            if vpnManager.isConnected {
                vpnIndicator
            }
        }
    }

    // MARK: - CPU Indicator

    var cpuIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(cpuColor)
            Text("\(Int(systemMonitor.cpuUsage.rounded()))%")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    var cpuColor: Color {
        if systemMonitor.cpuUsage > 80 { return .red }
        if systemMonitor.cpuUsage > 50 { return .orange }
        return .white.opacity(0.7)
    }

    // MARK: - RAM Indicator

    var ramIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "memorychip")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ramColor)
            Text("\(Int(systemMonitor.memoryPressure.rounded()))%")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    var ramColor: Color {
        if systemMonitor.memoryPressure > 80 { return .red }
        if systemMonitor.memoryPressure > 60 { return .orange }
        return .white.opacity(0.7)
    }

    // MARK: - VPN Indicator

    var vpnIndicator: some View {
        Image(systemName: "lock.shield.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.green)
    }
}

/// Detailed popover shown when clicking CPU/RAM indicators in the header
struct SystemStatusPopover: View {
    @ObservedObject var systemMonitor = SystemMonitor.shared
    @ObservedObject var bluetoothManager = BluetoothBatteryManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Status")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                // CPU
                HStack {
                    Label("CPU", systemImage: "cpu")
                    Spacer()
                    Text(String(format: "%.1f%%", systemMonitor.cpuUsage))
                        .foregroundStyle(.secondary)
                }
                // RAM
                HStack {
                    Label("Memory", systemImage: "memorychip")
                    Spacer()
                    Text(ramFormatted)
                        .foregroundStyle(.secondary)
                }
                // RAM Pressure bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15)).frame(height: 4)
                        Capsule()
                            .fill(ramPressureColor)
                            .frame(width: max(4, geo.size.width * systemMonitor.memoryPressure / 100), height: 4)
                    }
                }
                .frame(height: 4)
            }

            // Bluetooth devices
            if !bluetoothManager.devices.isEmpty {
                Divider()
                Text("Connected Devices")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(bluetoothManager.devices) { device in
                    HStack {
                        Image(systemName: bluetoothIcon(for: device.deviceName))
                        Text(device.deviceName)
                            .lineLimit(1)
                        Spacer()
                        Text("\(device.batteryPercent)%")
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding()
        .frame(width: 260)
        .foregroundColor(.white)
    }

    var ramFormatted: String {
        let usedGB = Double(systemMonitor.memoryUsed) / 1_073_741_824
        let totalGB = Double(systemMonitor.memoryTotal) / 1_073_741_824
        return String(format: "%.1f / %.1f GB", usedGB, totalGB)
    }

    var ramPressureColor: Color {
        if systemMonitor.memoryPressure > 80 { return .red }
        if systemMonitor.memoryPressure > 60 { return .orange }
        return .green
    }

    func bluetoothIcon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpod") { return "airpods" }
        if lower.contains("magic keyboard") || lower.contains("keyboard") { return "keyboard" }
        if lower.contains("magic mouse") || lower.contains("mouse") { return "magicmouse" }
        if lower.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if lower.contains("headphone") || lower.contains("headset") { return "headphones" }
        return "antenna.radiowaves.left.and.right"
    }
}

#Preview {
    SystemStatusPopover()
        .preferredColorScheme(.dark)
}
