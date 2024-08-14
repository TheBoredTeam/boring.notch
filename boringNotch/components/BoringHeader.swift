    //
    //  BoringHeader.swift
    //  boringNotch
    //
    //  Created by Harsh Vardhan  Goswami  on 04/08/24.
    //

import SwiftUI

struct BoringHeader: View {
    @StateObject var vm: BoringViewModel
    @State var percentage:Float
    @State var isCharging: Bool
    var body: some View {
        HStack {
            Text(vm.headerTitle)
                .contentTransition(.numericText())
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.gray)
            Spacer()
            HStack(spacing: 4){
                if(vm.settingsIconInNotch) {
                    SettingsLink(label: {
                        Capsule()
                            .fill(.black)
                            .frame(width: 30, height: 30)
                            .overlay {
                                Image(systemName: "gear")
                                    .foregroundColor(.white)
                                    .padding()
                                    .imageScale(.medium)
                            }
                    })
                    .buttonStyle(PlainButtonStyle())
                }
                if(vm.showBattery) {
                    BoringBatteryView(
                        batteryPercentage: percentage,
                        isPluggedIn: isCharging, batteryWidth: 30)
                }
                
            }
            .animation(vm.animation?.delay(0.6), value: vm.notchState)
            .font(.system(.headline, design: .rounded))
        }
    }}

#Preview {
    ZStack {
        Rectangle().fill(.black)
        BoringHeader(vm: .init(), percentage: 40, isCharging: true)
    }
}
