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
            )
            .contentTransition(.numericText())
            Spacer()
            HStack(spacing: 8){
                if vm.currentView != .menu {
                    Button(
                        action: {
                            print("Some Editor")
                            vm.openMenu()
                        },
                        label: {
                            Image(systemName: "ellipsis").foregroundColor(.white)
                        }).buttonStyle(PlainButtonStyle()).padding().frame(width: 30, height:30).font(.title)
                }
                BoringBatteryView(
                    batteryPercentage: percentage,
                    isPluggedIn: isCharging      )
            }
            .animation(vm.animation?.delay(1), value: vm.contentType)
            .font(.system(.headline, design: .rounded))
        }
    }}

#Preview {
    ZStack {
        Rectangle().fill(.black)
        BoringHeader(vm: .init(), percentage: 40, isCharging: true)
    }
}
