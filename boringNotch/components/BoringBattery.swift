import SwiftUI

struct BatteryView: View {
    @State var percentage: Float
    @State var isCharging: Bool
    var batteryWidth: CGFloat = 30
    var batteryHeight: CGFloat = 30
    var animationStyle: BoringAnimations = BoringAnimations()
    
    var icon: String {
        if isCharging {
            return "battery.100percent.bolt"
        }
        if percentage.isLessThanOrEqualTo(5.0){
            return "battery.0"
        }
        if percentage.isLessThanOrEqualTo(30) {
            return "battery.25percent"
        }
        if percentage.isLessThanOrEqualTo(60){
            return "battery.50percent"
        }
        if percentage.isLessThanOrEqualTo(90){
            return "battery.75percent"
        }
        if percentage.isLessThanOrEqualTo(100){
            return isCharging ? "battery.100percent.bolt" : "battery.100percent"
        }
        return "battery.0"
    }
    
     var batteryColor: Color {
        if isCharging {
            return .white
        } else {
            return .white
        }
    }
    
    var body: some View {
        Image(systemName: icon)
            .resizable()
            .fontWeight(.thin)
            .aspectRatio(contentMode: .fit)
            .foregroundColor(batteryColor).frame(
                width: batteryWidth,
                height: batteryHeight
            )
    }
}

struct BoringBatteryView: View {
    @State var batteryPercentage: Float = 0
    @State var isPluggedIn:Bool = false
    
    var body: some View {
        BatteryView(percentage: batteryPercentage, isCharging: isPluggedIn)}
}

#Preview {
    BatteryView(percentage: 20, isCharging: true)
}
