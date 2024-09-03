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
    
    var body: some View {
        VStack {
            if vm.notchState == .open {
                VStack(spacing: 10) {
                    BoringHeader(vm: vm, percentage: batteryModel.batteryPercentage, isCharging: batteryModel.isPluggedIn).padding(.leading, 6).padding(.trailing, 6).animation(.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.8), value: vm.notchState)
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
                            .cornerRadius(vm.notchState == .open ? vm.musicPlayerSizes.image.cornerRadius.opened.inset! : vm.musicPlayerSizes.image.cornerRadius.closed.inset!)
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
                                        HoverButton(icon: "backward.fill") {
                                            musicManager.previousTrack()
                                        }
                                        HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill") {
                                            print("tapped")
                                            musicManager.togglePlayPause()
                                        }
                                        HoverButton(icon: "forward.fill") {
                                            musicManager.nextTrack()
                                        }
                                    }
                                }
                                .allowsHitTesting(!vm.notchMetastability)
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
                        BoringBatteryView(batteryPercentage: batteryModel.batteryPercentage, isPluggedIn: batteryModel.isPluggedIn, batteryWidth: 30)}
                    
                    if vm.currentView != .menu && !batteryModel.showChargingInfo && (musicManager.isPlaying || !musicManager.isPlayerIdle) {
                        MusicVisualizer(avgColor: musicManager.avgColor, isPlaying: musicManager.isPlaying)
                            .frame(width: 30)
                    }
                }
            }
            
            if vm.notchState == .closed &&  vm.sneakPeak.show && !batteryModel.showChargingInfo {
                switch vm.sneakPeak.type {
                    case .music:
                        HStack() {
                            Image(systemName: "music.note").padding(.leading, 4)
                            Text(musicManager.songTitle)
                                .font(.headline)
                                .fontWeight(.regular)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                            
                            Spacer()
                        }.foregroundStyle(.gray, .gray).transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3)).delay(0.1))).padding(.horizontal, 4).padding(.vertical, 2)
                    default:
                        Text("")
                }
            }
        }
        .frame(width: calculateFrameWidthforNotchContent())
        .transition(.blurReplace.animation(.spring(.bouncy(duration: 0.5))))
    }
    
    func calculateFrameWidthforNotchContent() -> CGFloat? {
            // Calculate intermediate values
        let chargingInfoWidth: CGFloat = batteryModel.showChargingInfo ? 160 : 0
        let musicPlayingWidth: CGFloat = (!vm.firstLaunch && !batteryModel.showChargingInfo && (musicManager.isPlaying || (musicManager.isPlayerIdle ? vm.nothumanface : true))) ? 60 : -15
        
        let closedWidth: CGFloat = vm.sizes.size.closed.width! - 10
        
        let dynamicWidth: CGFloat = chargingInfoWidth + musicPlayingWidth + closedWidth
            // Return the appropriate width based on the notch state
        return vm.notchState == .open ? vm.musicPlayerSizes.player.size.opened.width : dynamicWidth + (vm.sneakPeak.show ? -12 : 0)
    }
}

#Preview {
    BoringNotch(vm: BoringViewModel(), batteryModel: BatteryStatusViewModel(vm: .init()), onHover: onHover).frame(width: 600, height: 500)
}
