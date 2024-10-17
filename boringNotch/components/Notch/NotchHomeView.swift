//
//  NotchHomeView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-18.
//

import SwiftUI

struct NotchHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var batteryModel: BatteryStatusViewModel
    @EnvironmentObject var webcamManager: WebcamManager
    
    let albumArtNamespace: Namespace.ID
    
    var body: some View {
        if !vm.firstLaunch {
            HStack(alignment: .top, spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                     if vm.lightingEffect {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .background(
                                Image(nsImage: musicManager.albumArt)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            )
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: vm.cornerRadiusScaling ? vm.musicPlayerSizes.image.cornerRadius.opened.inset! : vm.musicPlayerSizes.image.cornerRadius.closed.inset!))
                            .scaleEffect(x: 1.3, y: 2.8)
                            .rotationEffect(.degrees(92))
                            .blur(radius: 35)
                            .opacity(min(0.6, 1 - max(musicManager.albumArt.getBrightness(), 0.3)))
                            .onAppear {
                                print(musicManager.albumArt.getBrightness())
                            }
                    }
                  
                    Button {
                        musicManager.openMusicApp()
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .background(
                                    Image(nsImage: musicManager.albumArt)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                )
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: vm.cornerRadiusScaling ? vm.musicPlayerSizes.image.cornerRadius.opened.inset! : vm.musicPlayerSizes.image.cornerRadius.closed.inset!))
                                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                            
                            if vm.notchState == .open {
                                AppIcon(for: musicManager.bundleIdentifier)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 30, height: 30)
                                    .offset(x: 10, y: 10)
                                    .transition(.scale.combined(with: .opacity).animation(.bouncy.delay(0.3)))
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                VStack(alignment: .leading) {
                    GeometryReader { geo in
                        VStack(alignment: .leading, spacing: 4){
                            MarqueeText(musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white, frameWidth: geo.size.width)
                            MarqueeText(musicManager.artistName, font: .headline, nsFont: .headline, textColor: .gray, frameWidth: geo.size.width)
                                .fontWeight(.medium)
                        }
                    }
                    .padding(.top)
                    .padding(.leading, 5)
                    HStack(spacing: 0) {
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
                .buttonStyle(PlainButtonStyle())
                .opacity(vm.notchState == .closed ? 0 : 1)
                .blur(radius: vm.notchState == .closed ? 20 : 0)
                
                CalendarView()
                    .onContinuousHover { phase in
                        if vm.closeGestureEnabled {
                            switch phase {
                                case .active:
                                    vm.closeGestureEnabled = false
                                case .ended:
                                    vm.closeGestureEnabled = false
                            }
                        }
                    }
                
                if vm.showMirror {
                    CircularPreviewView(webcamManager: webcamManager)
                        .scaledToFit()
                        .opacity(vm.notchState == .closed ? 0 : 1)
                        .blur(radius: vm.notchState == .closed ? 20 : 0)
                }
                BoringSystemTiles()
                    .transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3)).delay(0.1)))
                    .opacity(vm.notchState == .closed ? 0 : 1)
                    .blur(radius: vm.notchState == .closed ? 20 : 0)
            }
        }
    }
}

#Preview {
    NotchHomeView(albumArtNamespace: Namespace().wrappedValue).environmentObject(MusicManager(vm: BoringViewModel())!).environmentObject(BoringViewModel()).environmentObject(BatteryStatusViewModel(vm: BoringViewModel())).environmentObject(WebcamManager())
}
