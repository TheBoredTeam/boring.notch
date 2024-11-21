    //
    //  NotchContentView.swift
    //  boringNotch
    //
    //  Created by Richard Kunkli on 13/08/2024.
    //

import SwiftUI
import Defaults

struct NotchContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var batteryModel: BatteryStatusViewModel
    @ObservedObject var webcamManager: WebcamManager
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    var body: some View {
        VStack(alignment: coordinator.firstLaunch ? .center : .leading, spacing: 0) {
            if vm.notchState == .open {
                BoringHeader()
                    .animation(.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.8), value: vm.notchState)
                    .padding(.top, 10)
                if coordinator.firstLaunch {
                    Spacer()
                    HelloAnimation().frame(width: 180, height: 60).onAppear(perform: {
                        vm.closeHello()
                    })
                    Spacer()
                }
            }
            
            if !coordinator.firstLaunch {
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
                        if(vm.notchState == .closed || coordinator.currentView == .home){
                            HStack (spacing: 6){
                                ZStack {
                                    Image(nsImage: musicManager.albumArt)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(
                                            width: vm.notchState == .open ? MusicPlayerImageSizes.size.opened.width : MusicPlayerImageSizes.size.closed.width,
                                            height: vm.notchState == .open ? MusicPlayerImageSizes.size.opened.height : MusicPlayerImageSizes.size.closed.height
                                        )
                                        .cornerRadius(vm.notchState == .open ? MusicPlayerImageSizes.cornerRadiusInset.opened : MusicPlayerImageSizes.cornerRadiusInset.closed)
                                        .scaledToFit()
                                        .padding(.leading, vm.notchState == .open ? 0 : 3)
                                    if vm.notchState == .open  {
                                        AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.music")
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
                            switch coordinator.currentView {
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
                        
                        if musicManager.isPlayerIdle == true && vm.notchState == .closed && !vm.expandingView.show && Defaults[.showNotHumanFace] {
                            MinimalFaceFeatures().transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3))))
                        }
                        
                        
                        if vm.notchState == .closed && vm.expandingView.show  {
                            if vm.expandingView.type == .battery {
                                BoringBatteryView(batteryPercentage: batteryModel.batteryPercentage, isPluggedIn: batteryModel.isPluggedIn, batteryWidth: 30, isInLowPowerMode: batteryModel.isInLowPowerMode)
                            } else {
                                ProgressIndicator(type: .text, progress: 0.01, color: Defaults[.accentColor]).padding(.trailing, 4)
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
        let chargingInfoWidth: CGFloat = vm.expandingView.show ? ((vm.expandingView.type == .download ? downloadSneakSize.width : batterySneakSize.width) + 10) : 0
        let musicPlayingWidth: CGFloat = (!coordinator.firstLaunch && !vm.expandingView.show && (musicManager.isPlaying || (musicManager.isPlayerIdle ? Defaults[.showNotHumanFace] : true))) ? 60 : -15
        
        let closedWidth: CGFloat = vm.closedNotchSize.width - 5
        
        let dynamicWidth: CGFloat = chargingInfoWidth + musicPlayingWidth + closedWidth
            // Return the appropriate width based on the notch state
        return vm.notchState == .open ? playerWidth + 30 : dynamicWidth + (coordinator.sneakPeek.show ? -12 : 0)
    }


}
