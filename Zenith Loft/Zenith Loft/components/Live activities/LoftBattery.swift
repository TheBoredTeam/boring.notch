//
//  LoftBattery.swift
//  Zenith Loft (LoftOS)
//  Created by You on 11/05/25
//
//  Clean-room battery HUD components:
//  - LoftBatteryIconView: compact battery glyph with fill + optional status icon
//  - LoftBatteryMenuView: popover with details + “Battery Settings” deep link
//  - LoftBatteryView: wrapper that shows percent + icon, handles press-to-popover
//
//  Notes:
//  - No external deps (no Defaults, no BN view model).
//  - Uses SF Symbols for icons (battery.*, bolt.fill, powerplug.fill).
//  - Expects battery data to be passed in (you can wire a provider later).
//

import SwiftUI
import AppKit

// Optional persisted user prefs (safe defaults).
private enum LoftPrefs {
    @AppStorage("loft_showBatteryPercentage") static var showBatteryPercentage: Bool = true
    @AppStorage("loft_showPowerStatusIcons")  static var showPowerStatusIcons: Bool  = true
}

// MARK: - Compact battery glyph with level fill and optional status icon

struct LoftBatteryIconView: View {
    var levelPercent: Float           // 0...100
    var isPluggedIn: Bool
    var isCharging: Bool
    var isLowPowerMode: Bool
    var width: CGFloat = 26
    var showStatusIcon: Bool = true   // typically true inside notifications/popover

    private var statusSymbolName: String? {
        if isCharging { return "bolt.fill" }
        if isPluggedIn { return "powerplug.fill" }
        return nil
    }

    private var color: Color {
        if isLowPowerMode { return .yellow }
        if levelPercent <= 20 && !isCharging && !isPluggedIn { return .red }
        if isCharging || isPluggedIn || levelPercent >= 100 { return .green }
        return .white
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            // Outline (battery SF symbol)
            Image(systemName: batterySymbolName(for: levelPercent))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.5))
                .frame(width: width)

            // Fill bar
            let innerW = max(0, (CGFloat(levelPercent) / 100.0) * (width - 6))
            RoundedRectangle(cornerRadius: 2.5)
                .fill(color)
                .frame(width: innerW, height: max(2, (width - 2.75) - 18))
                .padding(.leading, 2)

            // Status glyph overlay (bolt/plug), optional
            if showStatusIcon, let name = statusSymbolName, LoftPrefs.showPowerStatusIcons {
                Image(systemName: name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundColor(.white)
                    .frame(width: width, height: width) // center over battery
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private func batterySymbolName(for level: Float) -> String {
        switch level {
        case ..<10:   return "battery.0"
        case ..<35:   return "battery.25"
        case ..<65:   return "battery.50"
        case ..<90:   return "battery.75"
        default:      return "battery.100"
        }
    }

    private var accessibilityText: String {
        var parts: [String] = ["Battery \(Int(levelPercent))%"]
        if isLowPowerMode { parts.append("(Low Power Mode)") }
        if isCharging { parts.append("(Charging)") }
        if isPluggedIn && !isCharging { parts.append("(Plugged In)") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Popover content with details and deep link to Battery settings

struct LoftBatteryMenuView: View {
    var isPluggedIn: Bool
    var isCharging: Bool
    var levelPercent: Float
    var maxCapacityPercent: Float
    var minutesToFullCharge: Int
    var isLowPowerMode: Bool
    var onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Battery Status")
                    .font(.headline).fontWeight(.semibold)
                Spacer()
                Text("\(Int(levelPercent))%")
                    .font(.headline).fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Max Capacity: \(Int(maxCapacityPercent))%")
                    .font(.subheadline)
                if isLowPowerMode {
                    Label("Low Power Mode", systemImage: "bolt.circle")
                        .font(.subheadline)
                }
                if isCharging {
                    Label("Charging", systemImage: "bolt.fill")
                        .font(.subheadline)
                }
                if isPluggedIn {
                    Label("Plugged In", systemImage: "powerplug.fill")
                        .font(.subheadline)
                }
                if minutesToFullCharge > 0 {
                    Label("Time to Full Charge: \(minutesToFullCharge) min", systemImage: "clock")
                        .font(.subheadline)
                }
                if !isCharging && isPluggedIn && levelPercent >= 80 {
                    Label("Charging on Hold: Desktop Mode", systemImage: "desktopcomputer")
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 8)

            Divider().background(Color.white.opacity(0.2))

            Button(action: openBatteryPreferences) {
                Label("Battery Settings", systemImage: "gearshape")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
        .padding()
        .frame(width: 280)
        .foregroundColor(.white)
    }

    private func openBatteryPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            openURL(url)
            onDismiss()
        }
    }
}

// MARK: - Wrapper used in the HUD: percent + icon + press-to-popover

struct LoftBatteryView: View {
    // Inputs you’ll wire from your battery provider later:
    var isCharging: Bool = false
    var isLowPowerMode: Bool = false
    var isPluggedIn: Bool = false
    var levelPercent: Float = 0
    var maxCapacityPercent: Float = 100
    var minutesToFullCharge: Int = 0

    var iconWidth: CGFloat = 26
    var showPercent: Bool = true
    var showStatusIcon: Bool = true

    // UI state
    @State private var showPopup: Bool = false
    @State private var pressed: Bool = false
    @State private var hoveringPopover: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if showPercent && LoftPrefs.showBatteryPercentage {
                Text("\(Int(levelPercent))%")
                    .font(.callout)
                    .foregroundStyle(.white)
            }
            LoftBatteryIconView(
                levelPercent: levelPercent,
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                isLowPowerMode: isLowPowerMode,
                width: iconWidth,
                showStatusIcon: showStatusIcon
            )
        }
        .scaleEffect(pressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.18), value: pressed)
        // Press-to-toggle popover (works well in a tiny HUD surface)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation { pressed = true } }
                .onEnded   { _ in withAnimation {
                    pressed = false
                    showPopup.toggle()
                }}
        )
        .popover(isPresented: $showPopup, arrowEdge: .bottom) {
            LoftBatteryMenuView(
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                levelPercent: levelPercent,
                maxCapacityPercent: maxCapacityPercent,
                minutesToFullCharge: minutesToFullCharge,
                isLowPowerMode: isLowPowerMode,
                onDismiss: { showPopup = false }
            )
            .onHover { hovering in hoveringPopover = hovering }
        }
        // (Optional) you could broadcast popover state to the rest of your app here if needed.
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        LoftBatteryView(
            isCharging: true,
            isLowPowerMode: false,
            isPluggedIn: true,
            levelPercent: 72,
            maxCapacityPercent: 90,
            minutesToFullCharge: 35,
            iconWidth: 30
        )
        .frame(width: 240, height: 40)
        .background(.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 10))

        LoftBatteryView(
            isCharging: false,
            isLowPowerMode: false,
            isPluggedIn: false,
            levelPercent: 18,
            maxCapacityPercent: 88,
            minutesToFullCharge: 0,
            iconWidth: 30
        )
        .frame(width: 240, height: 40)
        .background(.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    .padding()
    .background(Color.black)
}
