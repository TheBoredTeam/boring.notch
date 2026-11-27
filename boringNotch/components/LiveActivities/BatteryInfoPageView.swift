//
//  BatteryInfoPageView.swift
//  boringNotch
//

import SwiftUI
import Defaults
import AppKit

enum BatterySymbolHelper {
    static func symbol(_ preferred: String, fallback: String) -> String {
        if NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil {
            return preferred
        }
        return fallback
    }

    static func symbol(_ candidates: [String], fallback: String = "questionmark.circle") -> String {
        for name in candidates where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return name
        }
        if NSImage(systemSymbolName: fallback, accessibilityDescription: nil) != nil {
            return fallback
        }
        return "questionmark.circle"
    }

    static func deviceSymbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("max") {
            return symbol(["airpodsmax", "airpodspro", "airpods"], fallback: "headphones")
        }
        if lower.contains("pro") {
            return symbol(["airpodspro", "airpods"], fallback: "headphones")
        }
        return symbol(["airpods", "airpodspro"], fallback: "headphones")
    }

    static func leftSymbol(for deviceName: String) -> String {
        let lower = deviceName.lowercased()
        if lower.contains("pro") {
            return symbol(["airpodpro.left", "airpod.left"], fallback: "l.circle")
        }
        return symbol(["airpod.left", "airpodpro.left"], fallback: "l.circle")
    }

    static func rightSymbol(for deviceName: String) -> String {
        let lower = deviceName.lowercased()
        if lower.contains("pro") {
            return symbol(["airpodpro.right", "airpod.right"], fallback: "r.circle")
        }
        return symbol(["airpod.right", "airpodpro.right"], fallback: "r.circle")
    }

    static func caseSymbol() -> String {
        symbol(
            [
                "airpodspro.chargingcase.wireless.fill",
                "airpodspro.chargingcase.wireless",
                "airpods.chargingcase.wireless.fill",
                "airpods.chargingcase.wireless",
                "earbuds.case.fill",
                "earbuds.case"
            ],
            fallback: "battery.0"
        )
    }

    static func batteryLevelSymbol(level: Int?) -> String {
        guard let level else { return symbol(["battery.0"], fallback: "questionmark.circle") }
        switch level {
        case 0..<13: return symbol(["battery.0percent", "battery.0"], fallback: "battery.0")
        case 13..<38: return symbol(["battery.25percent", "battery.25"], fallback: "battery.0")
        case 38..<63: return symbol(["battery.50percent", "battery.50"], fallback: "battery.0")
        case 63..<88: return symbol(["battery.75percent", "battery.75"], fallback: "battery.0")
        default: return symbol(["battery.100percent", "battery.100"], fallback: "battery.100")
        }
    }
}

struct BatteryInfoPageView: View {
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            macBatteryColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            if Defaults[.showAirPodsBattery] {
                Divider()
                    .background(Color.white.opacity(0.2))

                airPodsColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            batteryModel.refreshAirPodsBattery()
        }
    }

    private var macBatteryColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: BatterySymbolHelper.batteryLevelSymbol(level: Int(batteryModel.levelBattery)))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(macBatteryColor)
                Text("Mac")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer(minLength: 4)
                if Defaults[.showBatteryPercentage] {
                    Text("\(Int(batteryModel.levelBattery))%")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
            }

            if let maxCapacity = batteryModel.maxCapacity {
                compactRow("Max \(Int(maxCapacity))%", systemImage: "gauge.with.dots.needle.50percent")
            }

            if batteryModel.isInLowPowerMode {
                compactRow("Low Power", systemImage: "bolt.circle")
            }
            if batteryModel.isCharging {
                compactRow("Charging", systemImage: "bolt.fill", tint: .green)
            } else if batteryModel.isPluggedIn {
                compactRow("Plugged In", systemImage: "powerplug.fill")
            }
            if batteryModel.timeToFullCharge > 0 {
                compactRow("\(batteryModel.timeToFullCharge) min to full", systemImage: "clock")
            }
            if !batteryModel.isCharging && batteryModel.isPluggedIn && batteryModel.levelBattery >= 80 {
                compactRow("Hold: Desktop", systemImage: "desktopcomputer")
            }

            Button(action: openBatteryPreferences) {
                Label("Settings", systemImage: "gearshape")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .foregroundStyle(.white)
    }

    private var airPodsColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: BatterySymbolHelper.symbol(["airpodspro", "airpods"], fallback: "headphones"))
                    .font(.system(size: 18, weight: .medium))
                Text("AirPods")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)

            if batteryModel.airPodsDevices.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text(batteryModel.airPodsStatusMessage ?? "No connected AirPods detected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(batteryModel.airPodsDevices) { device in
                    AirPodsDeviceBatteryRow(device: device)
                }
            }
        }
    }

    private func compactRow(_ title: String, systemImage: String, tint: Color = .white) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .frame(width: 15)
                .foregroundStyle(tint == .white ? .white.opacity(0.85) : tint)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .font(.subheadline)
    }

    private var macBatteryColor: Color {
        if batteryModel.isInLowPowerMode { return .yellow }
        if batteryModel.levelBattery <= 20 && !batteryModel.isCharging && !batteryModel.isPluggedIn { return .red }
        if batteryModel.isCharging || batteryModel.isPluggedIn || batteryModel.levelBattery >= 100 { return .green }
        return .white
    }

    private func openBatteryPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            openURL(url)
        }
    }
}

private struct AirPodsDeviceBatteryRow: View {
    let device: AirPodsBatteryDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: BatterySymbolHelper.deviceSymbol(for: device.name))
                    .font(.system(size: 14, weight: .medium))
                Text(device.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.bottom, 4)

            HStack(alignment: .top, spacing: 12) {
                if let left = device.leftBattery {
                    batteryCell(icon: BatterySymbolHelper.leftSymbol(for: device.name), label: "L", percent: left, charging: device.leftIsCharging)
                }
                if let right = device.rightBattery {
                    batteryCell(icon: BatterySymbolHelper.rightSymbol(for: device.name), label: "R", percent: right, charging: device.rightIsCharging)
                }
                if let caseLevel = device.caseBattery {
                    batteryCell(icon: BatterySymbolHelper.caseSymbol(), label: "Case", percent: caseLevel, charging: device.caseIsCharging)
                }
            }

            if !device.hasBatteryData {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                    Text("Unavailable")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func batteryCell(icon: String, label: String, percent: Int, charging: Bool?) -> some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .frame(width: 20, height: 17)
                if charging == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                        .offset(x: 5, y: -3)
                }
            }
            Text("\(percent)%")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 42)
        .foregroundStyle(.white.opacity(0.9))
    }
}

#Preview {
    BatteryInfoPageView()
        .frame(width: 320, height: 260)
        .background(.black)
}
