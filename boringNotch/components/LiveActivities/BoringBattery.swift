import SwiftUI
import Defaults

/// A view that displays the battery status with an icon and charging indicator.
struct BatteryView: View {

    var levelBattery: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var batteryWidth: CGFloat = 26
    var isForNotification: Bool

    var icon: String = "battery.0"

    /// Determines the icon to display when charging.
    var iconStatus: String {
        if isCharging {
            return "bolt"
        }
        else if isPluggedIn {
            return "plug"
        }
        else {
            return ""
        }
    }

    /// Determines the color of the battery based on its status.
    var batteryColor: Color {
        if isInLowPowerMode {
            return .yellow
        } else if levelBattery <= 20 && !isCharging && !isPluggedIn {
            return .red
        } else if isCharging || isPluggedIn || levelBattery == 100 {
            return .green
        } else {
            return .white
        }
    }

    /// The outline is an SF Symbol scaled by width, so everything drawn
    /// inside it has to scale by width too.
    ///
    /// These were previously absolute: the fill height was
    /// `(batteryWidth - 2.75) - 18`, which only lands correctly at the
    /// default 30pt — at compact mode's 24pt it collapses to ~3pt, a sliver
    /// floating inside the outline. Expressing them relative to a reference
    /// width keeps the 30pt case numerically identical to before while
    /// making every other size correct.
    private static let referenceWidth: CGFloat = 30
    private var sizeScale: CGFloat { batteryWidth / Self.referenceWidth }

    /// 9.25pt at the 30pt reference — the interior cavity height of the
    /// battery symbol.
    private var fillHeight: CGFloat { 9.25 * sizeScale }
    /// Combined width of the outline stroke and terminal nub.
    private var fillInset: CGFloat { 6 * sizeScale }
    private var fillLeadingInset: CGFloat { 2 * sizeScale }

    var body: some View {
        ZStack(alignment: .leading) {

            Image(systemName: icon)
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.5))
                .frame(
                    width: batteryWidth + 1
                )

            RoundedRectangle(cornerRadius: 2.5 * sizeScale)
                .fill(batteryColor)
                .frame(
                    width: (CGFloat(levelBattery) / 100) * (batteryWidth - fillInset),
                    height: fillHeight
                )
                .padding(.leading, fillLeadingInset)

            if iconStatus != "" && (isForNotification || Defaults[.showPowerStatusIcons]) {
                ZStack {
                    Image(iconStatus)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                        .frame(
                            width: 17 * sizeScale,
                            height: 17 * sizeScale
                        )
                }
                .frame(width: batteryWidth, height: batteryWidth)
            }
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

/// A view that displays detailed battery information and settings.
struct BatteryMenuView: View {
    
    var isPluggedIn: Bool
    var isCharging: Bool
    var levelBattery: Float
    var maxCapacity: Float?
    var timeToFullCharge: Int
    var timeToDischarge: Int
    var isInLowPowerMode: Bool
    var maxAdapterWatts: Int = 0
    var onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    private var formattedTimeToDischarge: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(timeToDischarge * 60)) ?? ""
    }

    private var formattedTimeToFullCharge: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(timeToFullCharge * 60)) ?? ""
    }

    // Power status row ("Charging"/"Plugged In") with ": 140W" appended when the
    // adapter wattage is known and enabled. Watts is a separate Text so the
    // localized status key stays intact.
    private func powerStatusLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        let suffix = (Defaults[.showChargingWattage] && maxAdapterWatts > 0) ? ": \(maxAdapterWatts)W" : ""
        return Label {
            Text(title) + Text(suffix)
        } icon: {
            Image(systemName: icon)
        }
        .font(.subheadline)
        .fontWeight(.regular)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                Text("Battery Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text(
                    levelBattery / 100,
                    format: .percent.precision(.fractionLength(0))
                )
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if let maxCapacity {
                    Text(
                        "Max Capacity: \(maxCapacity / 100, format: .percent.precision(.fractionLength(0)))",
                        comment: "Battery maximum capacity."
                    )
                        .font(.subheadline)
                        .fontWeight(.regular)
                } else {
                    Text("Max Capacity: Not Available")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if isInLowPowerMode {
                    Label("Low Power Mode", systemImage: "bolt.circle")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if isCharging {
                    powerStatusLabel("Charging", icon: "bolt.fill")
                }
                if isPluggedIn && !isCharging {
                    powerStatusLabel("Plugged In", icon: "powerplug.fill")
                }
                if isCharging && timeToFullCharge > 0 {
                    Label("Time to Full Charge: \(formattedTimeToFullCharge)", systemImage: "clock")
                        .font(.subheadline)
                        .fontWeight(.regular)
                } else if isCharging && timeToFullCharge == -1 {
                    Label("Time to Full Charge: Calculating...", systemImage: "clock")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if !isCharging && !isPluggedIn && timeToDischarge > 0 {
                    Label("Time Until Empty: \(formattedTimeToDischarge)", systemImage: "clock")
                        .font(.subheadline)
                        .fontWeight(.regular)
                } else if !isCharging && !isPluggedIn && timeToDischarge == -1 {
                    Label("Time Until Empty: Calculating...", systemImage: "clock")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if !isCharging && isPluggedIn && levelBattery >= 80 {
                    Label("Charging on Hold: Desktop Mode", systemImage: "desktopcomputer")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                    
            }
            .padding(.vertical, 8)

            Divider().background(Color.white)

            Button(action: openBatteryPreferences) {
                Label("Battery Settings", systemImage: "gearshape")
                    .fontWeight(.regular)
            }
            .frame(maxWidth: .infinity)
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

/// A view that displays the battery status and allows interaction to show detailed information.
struct BoringBatteryView: View {
    
    @State var batteryWidth: CGFloat = 26
    var isCharging: Bool = false
    var isInLowPowerMode: Bool = false
    var isPluggedIn: Bool = false
    var levelBattery: Float = 0
    var maxCapacity: Float?
    var timeToFullCharge: Int = 0
    var timeToDischarge: Int = 0
    var maxAdapterWatts: Int = 0
    @State var isForNotification: Bool = false
    
    @State private var showPopupMenu: Bool = false
    @State private var isPressed: Bool = false
    @State private var isHoveringButton: Bool = false
    @State private var isHoveringPopover: Bool = false
    @State private var hideTask: Task<Void, Never>? = nil

    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        Button(action: {
            withAnimation {
                showPopupMenu.toggle()
            }
        }) {
            HStack {
                if Defaults[.showBatteryPercentage] {
                    Text(
                        levelBattery / 100,
                        format: .percent.precision(.fractionLength(0))
                    )
                        .font(.callout)
                        .foregroundStyle(.white)
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
        }
        .buttonStyle(ScaleButtonStyle())
        .popover(
            isPresented: $showPopupMenu,
            arrowEdge: .bottom) {
            BatteryMenuView(
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                levelBattery: levelBattery,
                maxCapacity: maxCapacity,
                timeToFullCharge: timeToFullCharge,
                timeToDischarge: timeToDischarge,
                isInLowPowerMode: isInLowPowerMode,
                maxAdapterWatts: maxAdapterWatts,
                onDismiss: {
                    showPopupMenu = false
                }
            )
            .onHover { hovering in
                isHoveringPopover = hovering
                if hovering {
                    hideTask?.cancel()
                    hideTask = nil
                } else {
                    scheduleHideIfNeeded()
                }
            }
        }
        .onChange(of: showPopupMenu) {
            vm.isBatteryPopoverActive = showPopupMenu
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
        }
    }

    private func scheduleHideIfNeeded() {
        if isHoveringButton || isHoveringPopover { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { showPopupMenu = false } }
        }
    }
}

#Preview {
    BoringBatteryView(
        batteryWidth: 30,
        isCharging: false,
        isInLowPowerMode: false,
        isPluggedIn: true,
        levelBattery: 80,
        maxCapacity: 100,
        timeToFullCharge: 10,
        timeToDischarge: 10,
        maxAdapterWatts: 140,
        isForNotification: false
    ).frame(width: 200, height: 200)
}
