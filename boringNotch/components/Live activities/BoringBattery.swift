import SwiftUI
import Defaults

/// A view that displays the battery status with an icon and charging indicator.
struct BatteryView: View {
    
    var percentage: Float
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var isInitialPlugIn: Bool
    var batteryWidth: CGFloat = 26
    var isForNotification: Bool
    
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
            
            if isCharging && (isForNotification || Defaults[.showPowerStatusIcons]) {
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

    private func formatTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }

    private var statusText: String {
        if isPluggedIn {
            return percentage >= 100 ? "Fully Charged" :
                   timeRemaining.map { "Charging - \(formatTime($0)) remaining" } ?? "Charging..."
        } else {
            return timeRemaining.map { "Battery - \(formatTime($0)) remaining" } ?? "On Battery"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            HStack {
                Label {
                    Text("Battery").fontWeight(.bold)
                } icon: {
                    Image(systemName: isPluggedIn ? "battery.100.bolt" : "battery.100")
                }
                Spacer()
                Text("\(Int(percentage))%").fontWeight(.bold)
            }
            .font(.title3)

            VStack(alignment: .leading, spacing: 8) {
                Text(statusText).fontWeight(.medium)
                if isInLowPowerMode {
                    Label("Low Power Mode", systemImage: "bolt.circle.fill").fontWeight(.medium)
                }
            }
            .font(.callout)
            
            Divider().background(.white)
            
            Button(action: openBatteryPreferences) {
                Label("Battery Settings", systemImage: "gear")
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        }
        .padding()
        .frame(width: 250)
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
    
    @State var batteryPercentage: Float = 0
    var isPluggedIn: Bool = false
    var isInLowPowerMode: Bool
    @State var batteryWidth: CGFloat = 26
    @State var isInitialPlugIn: Bool
    @State var timeRemaining: Int?
    @State private var showPopupMenu: Bool = false
    @State var isForNotification: Bool = false
    
    var body: some View {
        HStack {
            if Defaults[.showBatteryPercentage] {
                Text("\(Int32(batteryPercentage))%")
                    .font(.callout)
                    .foregroundStyle(.white)
            }
            BatteryView(
                percentage: batteryPercentage,
                isCharging: isPluggedIn,
                isInLowPowerMode: isInLowPowerMode,
                isInitialPlugIn: isInitialPlugIn,
                batteryWidth: batteryWidth,
                isForNotification: isForNotification
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
        isInLowPowerMode: false,
        batteryWidth: 30,
        isInitialPlugIn: false,
        timeRemaining: nil,
        isForNotification: true
    ).frame(width: 200, height: 200)
}
