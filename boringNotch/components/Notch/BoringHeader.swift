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
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @StateObject var tvm = TrayDrop.shared
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if (!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.boringShelf] {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
            
            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screens
                        .first(where: {$0.localizedName == coordinator.selectedScreen})?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width - 5)
                    .mask {
                        NotchShape()
                    }
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
                            isPluggedIn: batteryModel.isPluggedIn, batteryWidth: 30,
                            isInLowPowerMode: batteryModel.isInLowPowerMode
                        )
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel()).environmentObject(BatteryStatusViewModel(vm: BoringViewModel()))
}
