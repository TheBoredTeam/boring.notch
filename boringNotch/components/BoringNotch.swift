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
    
    var body: some View {
        ZStack {
            NotchShape(cornerRadius: vm.notchState == .open ? vm.sizes.corderRadius.opened.inset: vm.sizes.corderRadius.closed.inset)
                .fill(Color.black)
                .frame(width: vm.notchState == .open ? vm.sizes.size.opened.width : batteryModel.showChargingInfo ? CGFloat(vm.sizes.size.closed.width!) + CGFloat(70) : vm.sizes.size.closed.width, height: vm.notchState == .open ? vm.sizes.size.opened.height : vm.sizes.size.closed.height)
                .animation(.spring(), value: vm.notchState == .open)
                .shadow(color: .black.opacity(0.5), radius: 10)
            
            VStack {
                if vm.notchState == .open {
                    Spacer()
                    BoringHeader(vm: vm, percentage: batteryModel.batteryPercentage, isCharging: batteryModel.isPluggedIn).padding(.leading, 6).padding(.trailing, 10)
                }
                
                HStack(spacing: 10) {
                    if vm.notchState == .closed && batteryModel.showChargingInfo {
                        Text("Charging")
                    }
                    if (musicManager.isPlaying  || musicManager.lastUpdated.timeIntervalSinceNow > -vm.waitInterval) && (!batteryModel.showChargingInfo || vm.notchState == .open) && vm.currentView != .menu  {
                        
                        Image(nsImage: musicManager.albumArt).frame(width: vm.notchState == .open ? vm.musicPlayerSizes.image.size.opened.width: vm.musicPlayerSizes.image.size.closed.width, height:vm.notchState == .open ?vm.musicPlayerSizes.image.size.opened.height: vm.musicPlayerSizes.image.size.closed.height).cornerRadius(vm.notchState == .open ? vm.musicPlayerSizes.image.corderRadius.opened.inset! : vm.musicPlayerSizes.image.corderRadius.closed.inset!)
                        // Fit the image within the frame
                    }
                    
                    
                    
                    if vm.notchState == .open {
                        if vm.currentView == .menu {
                            BoringExtrasMenu(vm: vm).transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3))))
                        }
                        
                        if vm.currentView != .menu {
                            if musicManager.isPlaying == true || musicManager.lastUpdated.timeIntervalSinceNow > -vm.waitInterval {
                                VStack(alignment: .leading, spacing: 8) {
                                    VStack(alignment: .leading){
                                        Text(musicManager.songTitle)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                        Text(musicManager.artistName)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    HStack(spacing: 15) {
                                        Button(action: {
                                            musicManager.previousTrack()
                                        }) {
                                            Image(systemName: "backward.fill")
                                                .foregroundColor(.white).font(.title2)
                                        }.buttonStyle(PlainButtonStyle())
                                        Button(action: {
                                            musicManager.togglePlayPause()
                                        }) {
                                            Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                                                .foregroundColor(.white).font(.title)
                                        }.buttonStyle(PlainButtonStyle())
                                        Button(action: {
                                            musicManager.nextTrack()
                                        }) {
                                            Image(systemName: "forward.fill")
                                                .foregroundColor(.white).font(.title2)
                                        }.buttonStyle(PlainButtonStyle())
                                    }
                                }.transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3)).delay(vm.notchState == .closed ? 0 : 0.1)))
                            }
                            
                            if musicManager.isPlaying == false && musicManager.lastUpdated.timeIntervalSinceNow < -vm.waitInterval {
                                EmptyStateView(message:vm.emptyStateText )
                            }
                            
                        }
                    }
                    
                    if vm.currentView != .menu {
                        Spacer()
                    }
                    
                    
                    if musicManager.isPlaying == false && vm.notchState == .closed && !batteryModel.showChargingInfo {
                        
                        MinimalFaceFeatures().transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3))))
                    }
                    
                    if vm.notchState == .closed && batteryModel.showChargingInfo {
                        BoringBatteryView(batteryPercentage: batteryModel.batteryPercentage, isPluggedIn: batteryModel.isPluggedIn)
                    }
                    
                    if musicManager.isPlaying && !batteryModel.showChargingInfo && vm.currentView != .menu {
                        
                        MusicVisualizer()
                            .frame(width: 30).padding(.horizontal, vm.notchState == .open ? 8 : 2)
                        
                    }
                }
            }.frame(width: vm.notchState == .open ? 430 : batteryModel.showChargingInfo ? CGFloat(270) + CGFloat(60): 280)
                .padding(.horizontal, 10).padding(.vertical, vm.notchState == .open ? 10: 20).transition(.blurReplace.animation(.spring(.bouncy(duration: 0.5))))
        }.onHover { hovering in
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
    
    }
}

func onHover(){}

#Preview {
    ContentView(onHover:onHover, vm:.init(), batteryModel: .init())
}
