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
            Text(
                vm.headerTitle
            ).fontWeight(.medium)
            .contentTransition(.numericText())
            Spacer()
            HStack(spacing: 8){
                if vm.currentView != .menu {
                    Button(
                        action: {
                            vm.openMenu()
                        },
                        label: {
                            Image(systemName: "ellipsis").foregroundColor(.white)
                        }).buttonStyle(PlainButtonStyle()).padding().frame(width: 30, height:30).font(.title2)
                }
                if(vm.showBattery) {
                    BoringBatteryView(
                        batteryPercentage: percentage,
                        isPluggedIn: isCharging)
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
