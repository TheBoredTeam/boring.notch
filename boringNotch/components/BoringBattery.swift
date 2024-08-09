import SwiftUI

struct BatteryView: View {
    @State var percentage: Float
    @State var isCharging: Bool
    var batteryWidth: CGFloat = 26
    var batteryHeight: CGFloat = 26
    var animationStyle: BoringAnimations = BoringAnimations()
    
    var icon: String {
        return "battery.0"
    }
    
    var batteryColor: Color {
        if percentage.isLessThanOrEqualTo(20) {
            return .red
        } else {
            return .white
        }
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            
            Image(systemName: icon)
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.gray)
                .frame(
                    width: batteryWidth,
                    height: batteryHeight
                )
            
            RoundedRectangle(cornerRadius: 2)
                .fill(batteryColor)
                .frame(width: CGFloat(((CGFloat(CFloat(percentage)) / 100) * (batteryWidth - 6.5))), height: batteryHeight - 18.5)
                .padding(.trailing, 2.25)
            
            if isCharging {
                Image(systemName: "bolt.fill")
                    .foregroundColor(isCharging ? .green : .white)
                    .padding(.trailing, 2)
            }
            
        }
    }
}

struct BoringBatteryView: View {
    @State var batteryPercentage: Float = 0
    @State var isPluggedIn:Bool = false
    
    var body: some View {
        BatteryView(percentage: batteryPercentage, isCharging: isPluggedIn)}
}

#Preview {
    BatteryView(percentage: 70, isCharging: true).frame(width: 100)
}
