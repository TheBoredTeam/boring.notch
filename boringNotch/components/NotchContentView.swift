//
//  NotchContentView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 13/08/2024.
//

import SwiftUI

struct NotchContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var batteryModel: BatteryStatusViewModel
    
    func calculateNotchWidth() -> CGFloat {
        let isFaceVisible = (vm.nothumanface && musicManager.isPlayerIdle) || musicManager.isPlaying
        let baseWidth = vm.sizes.size.closed.width ?? 0
        
        let notchWidth: CGFloat = vm.notchState == .open
        ? vm.sizes.size.opened.width!
        : batteryModel.showChargingInfo
        ? baseWidth + 180
        : CGFloat(vm.firstLaunch ? 50 : 0) + baseWidth + (isFaceVisible ? 75 : 0)
        
        return notchWidth
    }
    var body: some View {
        VStack {
            if vm.notchState == .open {
                VStack(spacing: 10) {
                    BoringHeader(vm: vm, percentage: batteryModel.batteryPercentage, isCharging: batteryModel.isPluggedIn).padding(.leading, 6).padding(.trailing, 10).animation(.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.8), value: vm.notchState)
                    if vm.firstLaunch {
                        HelloAnimation().frame(width: 180, height: 60).onAppear(perform: {
                            vm.closeHello()
                        })
                    }
                }
            }
            
            if !vm.firstLaunch {
                
                HStack(spacing: 15) {
                    if vm.notchState == .closed && batteryModel.showChargingInfo {
                        Text("Charging").foregroundStyle(.white).padding(.leading, 4)
                    }
                    if !batteryModel.showChargingInfo && vm.currentView != .menu  {
                        
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
                    }
                    
                    if vm.notchState == .open {
                        if vm.currentView == .menu {
                            BoringExtrasMenu(vm: vm).transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3))))
                        }
                        
                        if vm.currentView != .menu {
                            if true {
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
                                                        .foregroundColor(.white)
                                                        .imageScale(.medium)
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
                                                        .foregroundColor(.white)
                                                        .contentTransition(.symbolEffect)
                                                        .imageScale(.large)
                                                }
                                        }
                                        Button {
                                            musicManager.nextTrack()
                                        } label: {
                                            Rectangle()
                                                .fill(.clear)
                                                .contentShape(Rectangle())
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
                                    }                                            }
                                .transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3)).delay(vm.notchState == .closed ? 0 : 0.1)))
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    
                    
                    if vm.currentView != .menu {
                        Spacer()
                    }
                    
                    if musicManager.isPlayerIdle == true && vm.notchState == .closed && !batteryModel.showChargingInfo && vm.nothumanface {
                        MinimalFaceFeatures().transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3))))
                    }
                    
                    
                    if vm.currentView != .menu && vm.notchState == .closed && batteryModel.showChargingInfo {
                        HStack {
                            Text("\(Int32(batteryModel.batteryPercentage))%").font(.callout)
                            BoringBatteryView(batteryPercentage: batteryModel.batteryPercentage, isPluggedIn: batteryModel.isPluggedIn, batteryWidth: 30)
                        }}
                    
                    if vm.currentView != .menu && !batteryModel.showChargingInfo && (musicManager.isPlaying || !musicManager.isPlayerIdle) {
                        MusicVisualizer(avgColor: musicManager.avgColor, isPlaying: musicManager.isPlaying)
                            .frame(width: 30)
                    }
                }
            }
        }
        .frame(width: calculateFrameWidthforNotchContent())
        .padding(.horizontal, 10)
        .padding(.vertical, vm.notchState == .open ? 10 : 5)
        .padding(.bottom, vm.notchState == .open ? 10 : 0)
        .transition(.blurReplace.animation(.spring(.bouncy(duration: 0.5))))
    }
    
    func calculateFrameWidthforNotchContent() -> CGFloat? {
        // Calculate intermediate values
        let chargingInfoWidth: CGFloat = batteryModel.showChargingInfo ? 160 : 0
        let musicPlayingWidth: CGFloat = (!vm.firstLaunch && !batteryModel.showChargingInfo && (musicManager.isPlaying || (musicManager.isPlayerIdle && vm.nothumanface))) ? 60 : -15
        
        let closedWidth: CGFloat = vm.sizes.size.closed.width! - 10
        
        let dynamicWidth: CGFloat = chargingInfoWidth + musicPlayingWidth + closedWidth
        print(closedWidth, chargingInfoWidth, musicPlayingWidth, dynamicWidth)
        // Return the appropriate width based on the notch state
        return vm.notchState == .open ? vm.musicPlayerSizes.player.size.opened.width : dynamicWidth
    }
}
