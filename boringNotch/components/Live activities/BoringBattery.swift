import SwiftUI

/// A view that displays the battery status with an icon and charging indicator.
struct BatteryView: View {
    
    @State var percentage: Float
    @State var isCharging: Bool
    @State var isInLowPowerMode: Bool
    @State var isInitialPlugIn: Bool
    
    var batteryWidth: CGFloat = 26
    var animationStyle: BoringAnimations = BoringAnimations()
    
    var icon: String = "battery.0"
    
    /// Determines the icon to display when charging.
    var chargingIcon: String {
        return isInitialPlugIn ? "powerplug.portrait.fill" : "bolt.fill"
    }
    
    /// Determines the color of the battery based on its status.
    var batteryColor: Color {
        switch (percentage, isInLowPowerMode, isCharging) {
        case (_, true, _):
            return .yellow
        case (...20, false, false):
            return .red
        case (_, _, true):
            return .green
        default:
            return .white
        }
    }

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
            
            RoundedRectangle(cornerRadius: 2.5)
                .fill(batteryColor)
                .frame(
                    width: CGFloat(((CGFloat(CFloat(percentage)) / 100) * (batteryWidth - 6))),
                    height: (batteryWidth - 2.75) - 18
                )
                .padding(.leading, 2)
            
            if isCharging {
                ZStack {
                    Image(systemName: chargingIcon)
                        .resizable()
                        .fontWeight(.thin)
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                        .frame(
                            width: batteryWidth * 0.4,
                            height: batteryWidth * 0.5
                        )
                }
                .frame(width: batteryWidth, height: batteryWidth)
            }
        }
    }
}

/// A view that displays detailed battery information and settings.
struct BatteryMenuView: View {
    
    var percentage: Float
    var isPluggedIn: Bool
    var timeRemaining: Int?
    var isInLowPowerMode: Bool
    var onDismiss: () -> Void
    
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    /// Determines the power source text based on the charging status.
    var powerSource: String {
        isPluggedIn ? "Power Source: AC Power" : "Power Source: Battery"
    }
    
    /// Determines the battery status text based on the charging status and time remaining.
    var batteryStatusText: String {
        switch (isPluggedIn, percentage, timeRemaining) {
        case (true, 100..., _):
            return "Fully charged"
        case (true, _, .some(let remaining)) where remaining > 0:
            let (hours, minutes) = minutesToHoursAndMinutes(remaining)
            return "Fully charged in \(hours)h \(minutes)m"
        case (false, _, .some(let remaining)) where remaining > 0:
            let (hours, minutes) = minutesToHoursAndMinutes(remaining)
            return "\(hours)h \(minutes)m remaining"
        default:
            return ""
        }
    }
    
    /// Determines the low power mode text.
    var lowPowerModeText: String {
        isInLowPowerMode ? "Low Power Mode: On" : ""
    }
    
    /// Combines the power source, battery status, and low power mode texts.
    var powerSourceText: String {
        [powerSource, batteryStatusText, lowPowerModeText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Determines the text color based on the color scheme.
    var textColor: Color {
        return colorScheme == .dark ? .white : .black
    }

    /// Converts minutes to hours and minutes.
    /// - Parameter minutes: The total minutes to convert.
    /// - Returns: A tuple containing hours and minutes.
    func minutesToHoursAndMinutes(_ minutes: Int) -> (hours: Int, minutes: Int) {
        return (minutes / 60, minutes % 60)
    }

    /// Opens the battery settings in System Preferences.
    func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            openURL(url)
            onDismiss()
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Battery")
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundColor(textColor)
                Spacer()
                Text("\(Int32(percentage))%")
                    .font(.callout)
                    .foregroundColor(textColor)
            }
            Text(powerSourceText)
                .font(.callout)
                .foregroundColor(textColor)
                .frame(
                    maxWidth: .infinity, 
                    alignment: .leading
                )
            Divider()
            Button(action: openBatterySettings) {
                Label("Battery Settings", systemImage: "gear")
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundColor(textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(minWidth: 200)
    }
}

/// A view that displays the battery status and allows interaction to show detailed information.
struct BoringBatteryView: View {
    
    @State var batteryPercentage: Float = 0
    @State var isPluggedIn: Bool = false
    @State var batteryWidth: CGFloat = 26
    @State var isInLowPowerMode: Bool
    @State var isInitialPlugIn: Bool
    @State var timeRemaining: Int?
    @State private var showPopupMenu: Bool = false
    
    var body: some View {
        HStack {
            Text("\(Int32(batteryPercentage))%")
                .font(.callout)
                .foregroundStyle(.white)
            BatteryView(
                percentage: batteryPercentage,
                isCharging: isPluggedIn,
                isInLowPowerMode: isInLowPowerMode,
                isInitialPlugIn: isInitialPlugIn,
                batteryWidth: batteryWidth
            )
        }
        .onTapGesture {
            showPopupMenu.toggle()
        }
        .popover(
            isPresented: $showPopupMenu,
            arrowEdge: .bottom) {
            BatteryMenuView(
                percentage: batteryPercentage,
                isPluggedIn: isPluggedIn,
                timeRemaining: timeRemaining,
                isInLowPowerMode: isInLowPowerMode,
                onDismiss: { showPopupMenu = false }
            )
        }
    }
}

#Preview {
    BoringBatteryView(
        batteryPercentage: 100,
        isPluggedIn: true,
        batteryWidth: 30,
        isInLowPowerMode: false,
        isInitialPlugIn: false,
        timeRemaining: nil
    ).frame(width: 200, height: 200)
}