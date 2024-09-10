    //
    //  NotchHomeView.swift
    //  boringNotch
    //
    //  Created by Hugo Persson on 2024-08-18.
    //

import SwiftUI

private var appIcons: AppIcons = AppIcons()

struct NotchHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var batteryModel: BatteryStatusViewModel
    @EnvironmentObject var webcamManager: WebcamManager
    
    let albumArtNamespace: Namespace.ID
    
    var body: some View {
        if !vm.firstLaunch {
            HStack(spacing: 10) {
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
                        Image(nsImage: appIcons.getIcon(bundleID: musicManager.bundleIdentifier)!)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 30, height: 30)
                            .offset(x: 10, y: 10)
                            .transition(.scale.combined(with: .opacity).animation(.bouncy.delay(0.3)))
                    }
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
                
                CalenderView().frame(
                    width: 220,
                    height: 100
                )
                
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
