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
        } else if isCharging {
            return .green
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
                .foregroundColor(.white.opacity(0.5))
                .frame(
                    width: batteryWidth + 1
                )
            
            RoundedRectangle(cornerRadius: 2.5)
                .fill(batteryColor)
                .frame(width: CGFloat(((CGFloat(CFloat(percentage)) / 100) * (batteryWidth - 6))), height: (batteryWidth - 2.75) - 18).padding(.leading, 2)
            if isCharging {
                Image(.bolt)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.yellow)
                    .frame(width: 16, height: 16)
                    .padding(.leading, 7)
                    .offset(y: -1)
            }
            
        }
    }
}

struct BoringBatteryView: View {
    @State var batteryPercentage: Float = 0
    @State var isPluggedIn:Bool = false
    @State var batteryWidth: CGFloat = 26
    
    var body: some View {
        HStack {
            Text("\(Int32(batteryPercentage))%")
                .font(.callout)
                .foregroundStyle(.white)
            BatteryView(percentage: batteryPercentage, isCharging: isPluggedIn, batteryWidth: batteryWidth)
        }
        
    }
}

#Preview {
    BoringBatteryView(
        batteryPercentage: 40,
        isPluggedIn: true,
        batteryWidth: 30
    ).frame(width: 200, height: 200)
}
