//
//  BoringNotch.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import SwiftUI

struct BoringNotch: View {
    @StateObject var vm: BoringViewModel
    let onHover: () -> Void
    @State private var isExpanded = false
    @State var showEmptyState = false
    @StateObject private var musicManager = MusicManager()
    @StateObject var batteryModel: BatteryStatusViewModel
    @State private var haptics: Bool = false
    
    var body: some View {
        ZStack {
            NotchShape(cornerRadius: vm.notchState == .open ? vm.sizes.corderRadius.opened.inset : vm.sizes.corderRadius.closed.inset)
                .fill(Color.black)
                .frame(width: vm.notchState == .open ? vm.sizes.size.opened.width : batteryModel.showChargingInfo ? CGFloat(vm.sizes.size.closed.width!) + CGFloat(100) : vm.sizes.size.closed.width, height: vm.notchState == .open ? vm.sizes.size.opened.height : vm.sizes.size.closed.height)
                .animation(.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.8), value: batteryModel.showChargingInfo)
                .shadow(color: .black.opacity(0.5), radius: 10)
            
            VStack {
                if vm.notchState == .open {
                    Spacer()
                    BoringHeader(vm: vm, percentage: batteryModel.batteryPercentage, isCharging: batteryModel.isPluggedIn).padding(.leading, 6).padding(.trailing, 10).animation(.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.8), value: vm.notchState)
                }
                
                HStack(spacing: 15) {
                    if vm.notchState == .closed && batteryModel.showChargingInfo {
                        Text("Charging")
                    }
                    if (musicManager.isPlaying || musicManager.lastUpdated.timeIntervalSinceNow > -vm.waitInterval) && (!batteryModel.showChargingInfo || vm.notchState == .open) && vm.currentView != .menu  {
                        
                        Image(nsImage: musicManager.albumArt)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: vm.notchState == .open ? vm.musicPlayerSizes.image.size.opened.width : vm.musicPlayerSizes.image.size.closed.width,
                                height: vm.notchState == .open ? vm.musicPlayerSizes.image.size.opened.height : vm.musicPlayerSizes.image.size.closed.height
                            )
                            .cornerRadius(vm.notchState == .open ? vm.musicPlayerSizes.image.corderRadius.opened.inset! : vm.musicPlayerSizes.image.corderRadius.closed.inset!)
                            .scaledToFit()
                            .padding(.leading, vm.notchState == .open ? 5 : 3)
                        // Fit the image within the frame
                    }
                    
                    
                    
                    if vm.notchState == .open {
                        if vm.currentView == .menu {
                            BoringExtrasMenu(vm: vm).transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3))))
                        }
                        
                        if vm.currentView != .menu {
                            if musicManager.isPlaying == true || musicManager.lastUpdated.timeIntervalSinceNow > -vm.waitInterval {
                                VStack(alignment: .leading, spacing: 5) {
                                    VStack(alignment: .leading, spacing: 3){
                                        Text(musicManager.songTitle)
                                            .font(.headline)
                                            .fontWeight(.regular)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(musicManager.artistName)
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                    HStack(spacing: 5) {
                                        Button {
                                            musicManager.previousTrack()
                                        } label: {
                                            Rectangle()
                                                .fill(.clear)
                                                .contentShape(Rectangle())
                                                .frame(width: 30, height: 30)
                                                .overlay {
                                                    Image(systemName: "backward.fill")
                                                        .imageScale(.medium)
                                                        .foregroundStyle(.white)
                                                }
                                        }
                                        Button {
                                            musicManager.togglePlayPause()
                                        } label: {
                                            Rectangle()
                                                .fill(.clear)
                                                .contentShape(Rectangle())
                                                .frame(width: 30, height: 30)
                                                .overlay {
                                                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                                                        .imageScale(.large)
                                                        .contentTransition(.symbolEffect)
                                                        .foregroundStyle(.white)
                                                }
                                        }
                                        Button {
                                            musicManager.nextTrack()
                                        } label: {
                                            Capsule()
                                                .fill(.black)
                                                .frame(width: 30, height: 30)
                                                .overlay {
                                                    Rectangle()
                                                        .fill(.clear)
                                                        .contentShape(Rectangle())
                                                        .frame(width: 30, height: 30)
                                                        .overlay {
                                                            Image(systemName: "forward.fill")
                                                                .imageScale(.medium)
                                                                .foregroundStyle(.white)
                                                        }
                                                    
                                                }
                                        }
                                    }
                                }
                                .transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3)).delay(vm.notchState == .closed ? 0 : 0.1)))
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            if musicManager.isPlaying == false && musicManager.lastUpdated.timeIntervalSinceNow < -vm.waitInterval {
                                EmptyStateView(message:vm.emptyStateText )
                            }
                            
                        }
                    }
                    
                    if vm.currentView != .menu {
                        Spacer()
                    }
                    
                    
                    if vm.notchState == .closed && batteryModel.showChargingInfo {
                        BoringBatteryView(batteryPercentage: batteryModel.batteryPercentage, isPluggedIn: batteryModel.isPluggedIn)
                    }
                    
                    if !batteryModel.showChargingInfo && vm.currentView != .menu {
                        
                        MusicVisualizer(avgColor: musicManager.albumArt.averageColor(), isPlaying: musicManager.isPlaying)
                            .frame(width: 30)
                            .padding(.horizontal, vm.notchState == .open ? 8 : 0)
                        
                    }
                }
            }
            .frame(width: vm.notchState == .open ? 430 : batteryModel.showChargingInfo ? CGFloat(270) + CGFloat(100) : 250)
            .padding(.horizontal, 10)
            .padding(.vertical, vm.notchState == .open ? 10 : 20)
            .padding(.bottom, vm.notchState == .open ? 5 : 0)
            .padding(.top, vm.notchState == .closed ? 5 : 0)
            .transition(.blurReplace.animation(.spring(.bouncy(duration: 0.5))))
        }
        .onHover { hovering in
            if ((vm.notchState == .closed) && vm.enableHaptics) {
                haptics.toggle()
            }
            withAnimation(vm.animation) {
                if hovering {
                    vm.open()
                } else {
                    vm.close()
                    vm.openMusic()
                }
                self.onHover()
            }
        }
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
}

func onHover(){}

#Preview {
    ContentView(onHover:onHover, vm:.init(), batteryModel: .init())
}
