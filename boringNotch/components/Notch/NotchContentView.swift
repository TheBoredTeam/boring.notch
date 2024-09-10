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
    @ObservedObject var webcamManager: WebcamManager

    var body: some View {
        VStack(alignment: vm.firstLaunch ? .center : .leading, spacing: 0) {
            if vm.notchState == .open {
                BoringHeader()
                    .animation(.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.8), value: vm.notchState)
                    .padding(.top, 10)
                if vm.firstLaunch {
                    Spacer()
                    HelloAnimation().frame(width: 180, height: 60).onAppear(perform: {
                        vm.closeHello()
                    })
                    Spacer()
                }
            }
            
            if !vm.firstLaunch {
                HStack(spacing: 14) {
                    if vm.notchState == .closed && vm.expandingView.show {
                        if(vm.expandingView.type == .battery){
                            Text("Charging").foregroundStyle(.white).padding(.leading, 4)
                        }
                        else {
                            if vm.expandingView.browser == .safari {
                                AppIcon(for: "com.apple.safari")
                            } else {
                                Image(.chrome).resizable().scaledToFit().frame(width: 30, height: 30)
                            }
                            
                        }
                    }
                    if !vm.expandingView.show {
                        if(vm.notchState == .closed || vm.currentView == .home){
                            HStack (spacing: 6){
                                ZStack {
                                    Image(nsImage: musicManager.albumArt)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(
                                            width: vm.notchState == .open ? vm.musicPlayerSizes.image.size.opened.width : vm.musicPlayerSizes.image.size.closed.width,
                                            height: vm.notchState == .open ? vm.musicPlayerSizes.image.size.opened.height : vm.musicPlayerSizes.image.size.closed.height
                                        )
                                        .cornerRadius(vm.notchState == .open ? vm.musicPlayerSizes.image.cornerRadius.opened.inset! : vm.musicPlayerSizes.image.cornerRadius.closed.inset!)
                                        .scaledToFit()
                                        .padding(.leading, vm.notchState == .open ? 0 : 3)
                                    if vm.notchState == .open  {
                                        AppIcon(for: musicManager.bundleIdentifier)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: vm.notchState == .open ? 30 : 10, height: vm.notchState == .open ? 30 : 10)
                                            .padding(.leading, vm.notchState == .open ? 70 : 20)
                                            .padding(.top, vm.notchState == .open ? 75 : 15)
                                            .transition(.scale.combined(with: .opacity).animation(.bouncy.delay(0.3)))
                                    }
                                }
                                
                            }
                        }
                        if vm.notchState == .open {
                            switch vm.currentView {
                            case .home:
                                EmptyView()
                                
                            case .shelf:
                                NotchShelfView()
                                
                            default:
                                Text("ERROR: VIEW NOT DEFINED")
                            }
                            
                            
                        }
                        
                        

                        
                        if  vm.notchState != .open {
                            Spacer()
                        }
                        
                        if musicManager.isPlayerIdle == true && vm.notchState == .closed && !vm.expandingView.show && vm.nothumanface {
                            MinimalFaceFeatures().transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3))))
                        }
                        
                        
                        if vm.notchState == .closed && vm.expandingView.show  {
                            if vm.expandingView.type == .battery {
                                BoringBatteryView(batteryPercentage: batteryModel.batteryPercentage, isPluggedIn: batteryModel.isPluggedIn, batteryWidth: 30)
                            } else {
                                ProgressIndicator(type: .text, progress: 0.01, color: vm.accentColor).padding(.trailing, 4)
                            }
                        }
                        
                    }
                        
                }
                .padding(.bottom, vm.expandingView.show ? 0 : vm.notchState == .closed ? 0 : 15)
                
                //            if vm.notchState == .open && !downloadWatcher.downloadFiles.isEmpty {
                //                DownloadArea().padding(.bottom, 15).transition(.blurReplace.animation(.spring(.bouncy(duration: 0.5)))).environmentObject(downloadWatcher)
                //            }
            }
        }
        .frame(width: calculateFrameWidthforNotchContent())
        .transition(.blurReplace.animation(.spring(.bouncy(duration: 0.5))))
    }
    
    func calculateFrameWidthforNotchContent() -> CGFloat? {
            // Calculate intermediate values
        let chargingInfoWidth: CGFloat = vm.expandingView.show ? ((vm.expandingView.type == .download ? downloadSneakSize.width : batterySenakSize.width) + 10) : 0
        let musicPlayingWidth: CGFloat = (!vm.firstLaunch && !vm.expandingView.show && (musicManager.isPlaying || (musicManager.isPlayerIdle ? vm.nothumanface : true))) ? 60 : -15
        
        let closedWidth: CGFloat = vm.sizes.size.closed.width! - 5
        
        let dynamicWidth: CGFloat = chargingInfoWidth + musicPlayingWidth + closedWidth
            // Return the appropriate width based on the notch state
        return vm.notchState == .open ? vm.musicPlayerSizes.player.size.opened.width! + 30 : dynamicWidth + (vm.sneakPeak.show ? -12 : 0)
    }


}
