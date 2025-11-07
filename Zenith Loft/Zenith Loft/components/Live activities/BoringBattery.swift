//
//  LoftBattery.swift
//  Zenith Loft (LoftOS)
//
//  Drop-in replacement for the original battery views.
//  - No `Defaults` dependency (uses @AppStorage with safe keys)
//  - No `BoringViewModel` dependency (optional callback instead)
//  - Uses SF Symbols: battery.*, bolt.fill, powerplug.fill
//

import SwiftUI

// MARK: - User prefs (safe defaults; replaceable later)
private enum LoftBatteryPrefs {
    @AppStorage("loft_showBatteryPercentage") static var showPercent: Bool = true
    @AppStorage("loft_showPowerStatusIcons")  static var showStatusIcons: Bool = true
}

// MARK: - Compact battery glyph with fill and optional status icon
/// NOTE: We keep the original name `BatteryView` so existing code compiles.
/// Internally this is fully “Loft”-style and has no external deps.
struct BatteryView: View {

    var levelBattery: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var batteryWidth: CGFloat = 26
    var isForNotification: Bool

    // original code had a `BoringAnimations`—not needed here
    var icon: String = "battery.0" // used with SF Symbols via systemName

    /// Chooses the small status glyph shown on top of the battery
    private var statusSymbolName: String? {
        if isCharging { return "bolt.fill" }
        if isPluggedIn { return "powerplug.fill" }
        return nil
    }

    /// Color for the fill bar
    private var batteryColor: Color {
        if isInLowPowerMode { return .yellow }
        if levelBattery <= 20 && !isCharging && !isPluggedIn { return .red }
        if isCharging || isPluggedIn || levelBattery >= 100 { return .green }
        return .white
    }

    var body: some View {
        ZStack(alignment: .leading) {

            Image(systemName: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.5))
                .frame(width: batteryWidth + 1)

            // fill bar
            let innerW = max(
                0,
                (CGFloat(levelBattery) / 100.0) * (batteryWidth - 6)
            )
            RoundedRectangle(cornerRadius: 2.5)
                .fill(batteryColor)
                .frame(width: innerW,
                       height: max(2, (batteryWidth - 2.75) - 18))
                .padding(.leading, 2)

            // overlay status icon (bolt/plug)
            if let name = statusSymbolName,
               (isForNotification || LoftBatteryPrefs.showStatusIcons) {
                Image(systemName: name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.white)
                    .frame(width: 17, height: 17)
                    .frame(width: batteryWidth, height: batteryWidth)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["Battery \(Int(levelBattery))%"]
        if isInLowPowerMode { parts.append("(Low Power Mode)") }
        if isCharging { parts.append("(Charging)") }
        else if isPluggedIn { parts.append("(Plugged In)") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Popover content (“Battery Settings” deep link)
struct BatteryMenuView: View {
    var isPluggedIn: Bool
    var isCharging: Bool
    var levelBattery: Float
    var maxCapacity: Float
    var timeToFullCharge: Int
    var isInLowPowerMode: Bool
    var onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                Text("Battery Status").font(.headline).fontWeight(.semibold)
                Spacer()
                Text("\(Int(levelBattery))%").font(.headline).fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Max Capacity: \(Int(maxCapacity))%").font(.subheadline)

                if isInLowPowerMode {
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
                if timeToFullCharge > 0 {
                    Label("Time to Full Charge: \(timeToFullCharge) min", systemImage: "clock")
                        .font(.subheadline)
                }
                if !isCharging && isPluggedIn && levelBattery >= 80 {
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
/// NOTE: We keep the original name `BoringBatteryView` so you don’t have to
/// rename call sites. There’s **no** dependency on BoringViewModel anymore.
/// If you want to know when the popover is active, pass a callback.
struct BoringBatteryView: View {

    // Inputs (wire from your battery provider later)
    @State var batteryWidth: CGFloat = 26
    var isCharging: Bool = false
    var isInLowPowerMode: Bool = false
    var isPluggedIn: Bool = false
    var levelBattery: Float = 0
    var maxCapacity: Float = 100
    var timeToFullCharge: Int = 0
    @State var isForNotification: Bool = false

    /// Optional: get notified when the popover becomes active/inactive
    var onPopoverActiveChanged: ((Bool) -> Void)? = nil

    // UI state
    @State private var showPopupMenu: Bool = false
    @State private var isPressed: Bool = false
    @State private var isHoveringPopover: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if LoftBatteryPrefs.showPercent {
                Text("\(Int(levelBattery))%")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }

            BatteryView(
                levelBattery: levelBattery,
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                isInLowPowerMode: isInLowPowerMode,
                batteryWidth: batteryWidth,
                isForNotification: isForNotification
            )
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.18), value: isPressed)
        // press to toggle popover (works well for tiny HUD surfaces)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation { isPressed = true } }
                .onEnded { _ in withAnimation {
                    isPressed = false
                    showPopupMenu.toggle()
                }}
        )
        .popover(isPresented: $showPopupMenu, arrowEdge: .bottom) {
            BatteryMenuView(
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                levelBattery: levelBattery,
                maxCapacity: maxCapacity,
                timeToFullCharge: timeToFullCharge,
                isInLowPowerMode: isInLowPowerMode,
                onDismiss: { showPopupMenu = false }
            )
            .onHover { hovering in
                isHoveringPopover = hovering
            }
        }
        .onChange(of: showPopupMenu) { _, _ in
            updateBatteryPopoverActiveState()
        }
        .onChange(of: isHoveringPopover) { _, _ in
            updateBatteryPopoverActiveState()
        }
    }

    private func updateBatteryPopoverActiveState() {
        onPopoverActiveChanged?(showPopupMenu && isHoveringPopover)
    }
}

// MARK: - Previews

#Preview {
    VStack(spacing: 20) {
        BoringBatteryView(
            batteryWidth: 30,
            isCharging: true,
            isInLowPowerMode: false,
            isPluggedIn: true,
            levelBattery: 72,
            maxCapacity: 92,
            timeToFullCharge: 35,
            isForNotification: false
        )
        .frame(width: 260, height: 44)
        .background(.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 10))

        BoringBatteryView(
            batteryWidth: 30,
            isCharging: false,
            isInLowPowerMode: false,
            isPluggedIn: false,
            levelBattery: 18,
            maxCapacity: 88,
            timeToFullCharge: 0,
            isForNotification: false
        )
        .frame(width: 260, height: 44)
        .background(.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    .padding()
    .background(Color.black)
}
