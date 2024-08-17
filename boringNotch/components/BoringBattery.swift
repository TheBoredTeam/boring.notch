import SwiftUI

struct BatteryView: View {
    @State var percentage: Float
    @State var isCharging: Bool
    var batteryWidth: CGFloat = 26
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
        ZStack(alignment: .leading) {
            Image(systemName: icon)
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.gray)
                .frame(
                    width: batteryWidth + 1
                )
            
            RoundedRectangle(cornerRadius: 2)
                .fill(batteryColor)
                .frame(width: CGFloat(((CGFloat(CFloat(percentage)) / 100) * (batteryWidth - 6))), height: (batteryWidth - 2.5) - 18).padding(.leading, 2).padding(.top, -0.5)
            if isCharging {
                Image(.bolt).resizable().aspectRatio(contentMode: .fit).foregroundColor(.yellow).frame(width: 16, height: 16).padding(.leading, 7).offset(y: -1)
            }
            
        }
    }
}

struct BoringBatteryView: View {
    @State var batteryPercentage: Float = 0
    @State var isPluggedIn:Bool = false
    @State var batteryWidth: CGFloat = 26
    
    var body: some View {
           if hasBattery() {
               HStack {
                   Text("\(Int32(batteryPercentage))%")
                       .font(.callout)
                   BatteryView(percentage: batteryPercentage, isCharging: isPluggedIn, batteryWidth: batteryWidth)
               }
           }
       }
}

#Preview {
    BatteryView(percentage: 100, isCharging: true, batteryWidth: 30).frame(width: 200, height: 200)
}
