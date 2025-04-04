import SwiftUI
import Defaults

// MARK: - LeftRoundedFill
struct LeftRoundedFill: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let radius: CGFloat = 4
        let height = rect.height
        let width = rect.width

        path.move(to: CGPoint(x: 0, y: height / 2))
        path.addArc(center: CGPoint(x: radius, y: radius),
                    radius: radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(270),
                    clockwise: false)
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: radius, y: height))
        path.addArc(center: CGPoint(x: radius, y: height - radius),
                    radius: radius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(180),
                    clockwise: false)
        path.closeSubpath()

        return path
    }
}

// MARK: - BatteryView
struct BatteryView: View {
    var levelBattery: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool

    var batteryWidth: CGFloat = 25
    var radius: CGFloat = 5
    var height: CGFloat { batteryWidth / 1.9 }
    var capWidth: CGFloat { 1.5 }

    /// Battery fill color logic
    var batteryColor: Color {
        if isInLowPowerMode {
            return .yellow
        } else if levelBattery <= 20 && !isCharging && !isPluggedIn {
            return .red
        } else if levelBattery > 20 && !isCharging && !isPluggedIn {
            return .white
        } else {
            return .green
        }
    }

    /// Battery background color logic
    var backgroundColor: Color {
        return batteryColor.opacity(0.3)
    }

    /// Battery cap color logic
    var capColor: Color {
        levelBattery == 100 ? batteryColor : backgroundColor
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Battery container + cap
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: radius)
                    .fill(backgroundColor)
                    .frame(width: batteryWidth, height: height)

                RoundedRectangle(cornerRadius: radius)
                    .fill(capColor)
                    .frame(width: capWidth, height: height * 0.4)
                    .padding(.leading, 1)
            }

            // Battery fill
            GeometryReader { _ in
                let fillWidth = max(CGFloat(levelBattery) / 100 * batteryWidth, 2)

                if levelBattery == 100 {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(batteryColor)
                        .frame(width: fillWidth, height: height)
                } else {
                    LeftRoundedFill()
                        .fill(batteryColor)
                        .frame(width: fillWidth, height: height)
                }
            }
            .frame(width: batteryWidth, height: height)
        }
    }
}

// MARK: - BoringBatteryView
struct BoringBatteryView: View {
    var batteryWidth: CGFloat = 25
    var isCharging: Bool = false
    var isInLowPowerMode: Bool = false
    var isPluggedIn: Bool = false
    var levelBattery: Float = 0
    var maxCapacity: Float = 0
    var timeToFullCharge: Int = 0
    var isForNotification: Bool = false

    /// Text color logic matching your battery logic
    private var batteryTextColor: Color {
        if isCharging || isPluggedIn {
            return .green
        } else if levelBattery <= 20 {
            return .red
        } else {
            // If above 20% and not plugged in or charging, it's white
            return .white
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            // Show "xx%" if user wants battery % or it's for notifications
            if Defaults[.showBatteryPercentage] || isForNotification {
                Text("\(Int(levelBattery))%")
                    .font(.callout)
                    .foregroundStyle(batteryTextColor)
            }

            BatteryView(
                levelBattery: levelBattery,
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                isInLowPowerMode: isInLowPowerMode,
                batteryWidth: batteryWidth
            )
        }
    }
}

// MARK: - Previews
#Preview("Battery Previews") {
    VStack(spacing: 12) {
        BoringBatteryView(
            batteryWidth: 20,
            isCharging: false,
            isInLowPowerMode: false,
            isPluggedIn: false,
            levelBattery: 15,
            isForNotification: true
        )
        .padding()
        .background(.black)

        BoringBatteryView(
            batteryWidth: 20,
            isCharging: false,
            isInLowPowerMode: false,
            isPluggedIn: false,
            levelBattery: 60,
            isForNotification: true
        )
        .padding()
        .background(.black)
        
        BoringBatteryView(
            batteryWidth: 20,
            isCharging: true,
            isInLowPowerMode: false,
            isPluggedIn: true,
            levelBattery: 60,
            isForNotification: true
        )
        .padding()
        .background(.black)

        BoringBatteryView(
            batteryWidth: 20,
            isCharging: true,
            isInLowPowerMode: false,
            isPluggedIn: true,
            levelBattery: 100,
            isForNotification: true
        )
        .padding()
        .background(.black)
    }
}
