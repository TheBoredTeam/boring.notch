//
//  BoringNotch.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
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
    
    init(vm: BoringViewModel, batteryModel: BatteryStatusViewModel, onHover: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: vm)
        _musicManager = StateObject(wrappedValue: MusicManager(vm: vm))
        _batteryModel = StateObject(wrappedValue: batteryModel)
        self.onHover = onHover
    }
    
    var body: some View {
        ZStack {
            NotchShape(cornerRadius: vm.notchState == .open ? vm.sizes.corderRadius.opened.inset : vm.sizes.corderRadius.closed.inset)
                .fill(Color.black)
                .frame(width: vm.notchState == .open ? vm.sizes.size.opened.width : batteryModel.showChargingInfo ? CGFloat(vm.sizes.size.closed.width!) + CGFloat(200) :(vm.firstLaunch ? 50 : 0) + (vm.sizes.size.closed.width ?? 0) + CGFloat(vm.nothumanface || musicManager.isPlaying ? 100 : 0), height: vm.notchState == .open ? (vm.sizes.size.opened.height!) : vm.sizes.size.closed.height)
                .animation(notchAnimation, value: batteryModel.showChargingInfo)
                .animation(notchAnimation, value: musicManager.isPlaying).animation(.smooth, value: vm.firstLaunch)
                .shadow(color: .black.opacity(0.5), radius: 10)
            
            VStack {
                if vm.notchState == .open {
                    Spacer()
                    VStack(spacing: 10) {
                        BoringHeader(vm: vm, percentage: batteryModel.batteryPercentage, isCharging: batteryModel.isPluggedIn).padding(.leading, 6).padding(.trailing, 10).animation(.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.8), value: vm.notchState)
                        
                        if vm.firstLaunch {
                            HelloAnimation().frame(width: 200, height: vm.sizes.size.opened.height! - 30 ).onAppear(perform: {
                                vm.closeHello()
                            }).padding(.vertical, 100).padding(.top, 70)
                        }
                        
                    }
                    
                }
                
                if !vm.firstLaunch {
                    
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
                                .padding(.leading, vm.notchState == .open ? 5 : 0)
                        }
                        
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
                                            Capsule()
                                                .fill(.black)
                                                .frame(width: 30, height: 30)
                                                .overlay {
                                                    Image(systemName: "backward.fill")
                                                        .foregroundColor(.white)
                                                        .imageScale(.medium)
                                                }
                                        }
                                        Button {
                                            musicManager.togglePlayPause()
                                        } label: {
                                            Capsule()
                                                .fill(.black)
                                                .frame(width: 30, height: 30)
                                                .overlay {
                                                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                                                        .foregroundColor(.white)
                                                        .contentTransition(.symbolEffect)
                                                        .imageScale(.large)
                                                }
                                        }
                                        Button {
                                            musicManager.nextTrack()
                                        } label: {
                                            Capsule()
                                                .fill(.black)
                                                .frame(width: 30, height: 30)
                                                .overlay {
                                                    Capsule()
                                                        .fill(.black)
                                                        .frame(width: 30, height: 30)
                                                        .overlay {
                                                            Image(systemName: "forward.fill")
                                                                .foregroundColor(.white)
                                                                .imageScale(.medium)
                                                            
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
                            
                            if musicManager.isPlaying == false && vm.notchState == .closed && !batteryModel.showChargingInfo && vm.nothumanface {
                                
                                
                                MinimalFaceFeatures().transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3))))
                            }
                            
                            Spacer()
                        }
                        
                        
                        if vm.notchState == .closed && batteryModel.showChargingInfo {
                            BoringBatteryView(batteryPercentage: batteryModel.batteryPercentage, isPluggedIn: batteryModel.isPluggedIn)
                        }
                        
                        if musicManager.isPlaying && !batteryModel.showChargingInfo && vm.currentView != .menu {
                            MusicVisualizer(avgColor: musicManager.avgColor, isPlaying: musicManager.isPlaying)
                                .frame(width: 30).padding(.horizontal, vm.notchState == .open ? 8 : 2)
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
            .frame(width: vm.notchState == .open
                   ? vm.musicPlayerSizes.player.size.opened.width : (batteryModel.showChargingInfo ? CGFloat(180):
                                                                        ((musicManager.isPlaying || vm.nothumanface) ? CGFloat(85) : CGFloat(0))) + (vm.sizes.size.closed.width! - 20))
            .padding(.horizontal, 10)
            .padding(.vertical, vm.notchState == .open ? 10 : 20)
            .padding(.bottom, vm.notchState == .open ? 5 : 0)
            .padding(.top, vm.notchState == .closed ? 5 : 0)
            .transition(.blurReplace.animation(.spring(.bouncy(duration: 0.5))))
        }
        .onHover { hovering in
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
    ContentView(onHover:onHover, vm:.init(), batteryModel: .init(vm: BoringViewModel())).environmentObject(BoringViewModel())
}
