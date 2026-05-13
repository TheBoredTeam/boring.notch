//
//  BoringHeader.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

struct BoringHeader: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var caffeine = CaffeinateManager.shared
    @StateObject var tvm = ShelfStateViewModel.shared
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
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if isOSDType(coordinator.sneakPeekState(for: vm.screenUUID).type) && coordinator.shouldShowSneakPeek(on: vm.screenUUID) && Defaults[.showOpenNotchOSD] {
                        OpenNotchOSD(
                             type: coordinator.binding(for: vm.screenUUID).type,
                             value: coordinator.binding(for: vm.screenUUID).value,
                             icon: coordinator.binding(for: vm.screenUUID).icon,
                             accent: coordinator.binding(for: vm.screenUUID).accent
                        )
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        if Defaults[.showMirror] {
                            Button(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "web.camera")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.settingsIconInNotch] {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                                
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "gear")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.showCaffeinateButton] {
                            if caffeine.isActive {
                                Button(action: {
                                    caffeine.disable()
                                }) {
                                    caffeineCapsule
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help(caffeineHelpText)
                            } else {
                                Menu {
                                    Button("5 minutes") { caffeine.enable(duration: 5 * 60) }
                                    Button("15 minutes") { caffeine.enable(duration: 15 * 60) }
                                    Button("30 minutes") { caffeine.enable(duration: 30 * 60) }
                                    Button("1 hour") { caffeine.enable(duration: 60 * 60) }
                                    Button("2 hours") { caffeine.enable(duration: 2 * 60 * 60) }
                                    Divider()
                                    Button("Indefinite") { caffeine.enable(duration: nil) }
                                } label: {
                                    caffeineCapsule
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .frame(width: 30, height: 30)
                                .help("Caffeinate: off")
                            }
                        }
                        if Defaults[.showBatteryIndicator] {
                            BoringBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                maxCapacity: batteryModel.maxCapacity,
                                timeToFullCharge: batteryModel.timeToFullCharge,
                                timeToDischarge: batteryModel.timeToDischarge,
                                isForNotification: false
                            )
                        }
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    private var caffeineCapsule: some View {
        Capsule()
            .fill(.black)
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: caffeine.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundColor(caffeine.isActive ? .yellow : .white)
                    .padding()
                    .imageScale(.medium)
            }
    }

    private var caffeineHelpText: String {
        if let endDate = caffeine.endDate {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Caffeinate: on until \(formatter.string(from: endDate))"
        }
        return "Caffeinate: on (system stays awake)"
    }

    func isOSDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
