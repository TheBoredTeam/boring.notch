//
//  BoringHeader.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import SwiftUI
import Defaults

struct BoringHeader: View {
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var batteryModel: BatteryStatusViewModel
    @StateObject var tvm = TrayDrop.shared
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if (!tvm.isEmpty || vm.alwaysShowTabs) && Defaults[.boringShelf] {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    Text(vm.headerTitle)
                        .contentTransition(.numericText())
                        .font(.system(size: 12, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.2), value: vm.notchState)
            .zIndex(2)
            
            if vm.notchState == .open {
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.sizes.size.closed.width! - 5)
                    .shadow(color: .black, radius: 30, x: -25, y: 10)
                    .zIndex(1)
            }
            
            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if Defaults[.settingsIconInNotch] {
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
                    if Defaults[.showBattery] {
                        BoringBatteryView(
                            batteryPercentage: batteryModel.batteryPercentage,
                            isPluggedIn: batteryModel.isPluggedIn, batteryWidth: 30)
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.2), value: vm.notchState)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel()).environmentObject(BatteryStatusViewModel(vm: BoringViewModel()))
}
