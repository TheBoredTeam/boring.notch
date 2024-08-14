    //
    //  BoringViewModel.swift
    //  boringNotch
    //
    //  Created by Harsh Vardhan  Goswami  on 04/08/24.
    //

import SwiftUI

var notchAnimation = Animation.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.8)

struct BoringNotch: View {
    @StateObject var vm: BoringViewModel
    let onHover: () -> Void
    @State private var isExpanded = false
    @State var showEmptyState = false
    @StateObject private var musicManager: MusicManager
    @StateObject var batteryModel: BatteryStatusViewModel
    @State private var haptics: Bool = false
    
    @State private var hoverStartTime: Date?
    @State private var hoverTimer: Timer?
    @State private var hoverAnimation: Bool = false
    
    init(vm: BoringViewModel, batteryModel: BatteryStatusViewModel, onHover: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: vm)
        _musicManager = StateObject(wrappedValue: MusicManager(vm: vm)!)
        _batteryModel = StateObject(wrappedValue: batteryModel)
        self.onHover = onHover
    }
    
    func calculateNotchWidth() -> CGFloat {
        let isFaceVisible = (musicManager.isPlayerIdle ? vm.nothumanface: true) || musicManager.isPlaying
        let baseWidth = vm.sizes.size.closed.width ?? 0
        
        let notchWidth: CGFloat = vm.notchState == .open
        ? vm.sizes.size.opened.width!
        : batteryModel.showChargingInfo
        ? baseWidth + 160
        : CGFloat(vm.firstLaunch ? 50 : 0) + baseWidth + (isFaceVisible ? 65 : 0)
        
        return notchWidth + (hoverAnimation ? 16 : 0)
    }
    
    var body: some View {
        Rectangle()
            .foregroundColor(.black)
            .mask(NotchShape(cornerRadius: vm.notchState == .open ? vm.sizes.cornerRadius.opened.inset : (vm.sneakPeak.show ? 4 : 0) + vm.sizes.cornerRadius.closed.inset!))
            .frame(width: calculateNotchWidth(), height: vm.notchState == .open ? (vm.sizes.size.opened.height!) : vm.sizes.size.closed.height! + (hoverAnimation ? 8 : !batteryModel.showChargingInfo && vm.sneakPeak.show ? 25 : 0))
            .animation(notchAnimation, value: batteryModel.showChargingInfo)
            .animation(notchAnimation, value: musicManager.isPlaying)
            .animation(notchAnimation, value: musicManager.lastUpdated)
            .animation(notchAnimation, value: musicManager.isPlayerIdle)
            .animation(.smooth, value: vm.firstLaunch)
            .animation(notchAnimation, value: vm.sneakPeak.show)
            .overlay {
                NotchContentView()
                    .environmentObject(vm)
                    .environmentObject(musicManager)
                    .environmentObject(batteryModel)
            }
            .clipped()
            .onHover { hovering in
                if hovering {
                    if ((vm.notchState == .closed) && vm.enableHaptics) {
                        haptics.toggle()
                    }
                    startHoverTimer()
                } else {
                    vm.notchMetastability = true
                    cancelHoverTimer()
                    if vm.notchState == .open {
                        withAnimation(.smooth) {
                            vm.close()
                            vm.openMusic()
                        }
                    }
                }
            }
            .shadow(color: vm.notchState == .open ? .black : hoverAnimation ? .black.opacity(0.5) : .clear, radius: 10)
            .sensoryFeedback(.levelChange, trigger: haptics)
            .onChange(of: batteryModel.isPluggedIn, { oldValue, newValue in
                withAnimation(.spring(response: 1, dampingFraction: 0.8, blendDuration: 0.7)) {
                    if newValue {
                        batteryModel.showChargingInfo = true
                    } else {
                        batteryModel.showChargingInfo = false
                    }
                }
            })
            .environmentObject(vm)
    }
    
    
    private func startHoverTimer() {
        hoverStartTime = Date()
        hoverTimer?.invalidate()
        withAnimation(vm.animation) {
            hoverAnimation = true
        }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            checkHoverDuration()
        }
    }
    
    private func checkHoverDuration() {
        guard let startTime = hoverStartTime else { return }
        let hoverDuration = Date().timeIntervalSince(startTime)
        if hoverDuration >= vm.minimumHoverDuration {
            withAnimation() {
                vm.open()
                vm.notchMetastability = false
            }
            cancelHoverTimer()
        }
    }
    
    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverStartTime = nil
        withAnimation(vm.animation) {
            hoverAnimation = false
        }
    }
}

func onHover(){}

#Preview {
    BoringNotch(vm: BoringViewModel(), batteryModel: BatteryStatusViewModel(vm: .init()), onHover: onHover).frame(width: 600, height: 500)
}
