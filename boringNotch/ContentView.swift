//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import KeyboardShortcuts
import SwiftUI
import Defaults
import SwiftUIIntrospect

struct ContentView: View {    
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var batteryModel: BatteryStatusViewModel
    @EnvironmentObject var musicManager: MusicManager
    @StateObject var webcamManager: WebcamManager = .init()
    
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    
    @State private var hoverStartTime: Date?
    @State private var hoverTimer: Timer?
    @State private var hoverAnimation: Bool = false
    
    @State private var gestureProgress: CGFloat = .zero
    
    @State private var haptics: Bool = false
    
    @Namespace var albumArtNamespace
    
    @Default(.useMusicVisualizer) var useMusicVisualizer
    
    var body: some View {
        ZStack(alignment: .top) {
            NotchLayout()
                .padding(.horizontal, vm.notchState == .open ? Defaults[.cornerRadiusScaling] ? (cornerRadiusInsets.opened) : (cornerRadiusInsets.closed - 5) : 12)
                .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                .frame(maxWidth: (((musicManager.isPlaying || !musicManager.isPlayerIdle) && vm.notchState == .closed && coordinator.showMusicLiveActivityOnClosed) || (vm.expandingView.show && (vm.expandingView.type == .battery)) || Defaults[.inlineHUD]) ? nil : vm.notchSize.width + ((hoverAnimation || (vm.notchState == .closed)) ? 20 : 0) + gestureProgress, maxHeight: ((coordinator.sneakPeek.show && coordinator.sneakPeek.type != .music) || (coordinator.sneakPeek.show && coordinator.sneakPeek.type == .music && vm.notchState == .closed)) ? nil : vm.notchSize.height + (hoverAnimation ? 8 : 0) + gestureProgress / 3, alignment: .top)
                .background(.black)
                .mask {
                    NotchShape(cornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling]) ? cornerRadiusInsets.opened : cornerRadiusInsets.closed)
                }
                .frame(width: vm.notchState == .closed ? (((musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.showMusicLiveActivityOnClosed) || (vm.expandingView.show && (vm.expandingView.type == .battery)) || (Defaults[.inlineHUD] && coordinator.sneakPeek.show && coordinator.sneakPeek.type != .music)) ? nil : vm.closedNotchSize.width + (hoverAnimation ? 20 : 0) + gestureProgress : nil, height: vm.notchState == .closed ? vm.closedNotchSize.height + (hoverAnimation ? 8 : 0) + gestureProgress / 3 : nil, alignment: .top)
                .conditionalModifier(Defaults[.openNotchOnHover]) { view in
                    view
                        .onHover { hovering in
                            if hovering {
                                withAnimation(.bouncy) {
                                    hoverAnimation = true
                                }
                                
                                if (vm.notchState == .closed) && Defaults[.enableHaptics] {
                                    haptics.toggle()
                                }
                                
                                if coordinator.sneakPeek.show {
                                    return
                                }
                                
                                startHoverTimer()
                            } else {
                                withAnimation(.bouncy) {
                                    hoverAnimation = false
                                }
                                cancelHoverTimer()
                                
                                if vm.notchState == .open {
                                    vm.close()
                                }
                            }
                        }
                }
                .conditionalModifier(!Defaults[.openNotchOnHover]) { view in
                    view
                        .onHover { hovering in
                            if hovering {
                                withAnimation(vm.animation) {
                                    hoverAnimation = true
                                }
                            } else {
                                withAnimation(vm.animation) {
                                    hoverAnimation = false
                                }
                                if vm.notchState == .open {
                                    vm.close()
                                }
                            }
                        }
                        .onTapGesture {
                            if (vm.notchState == .closed) && Defaults[.enableHaptics] {
                                haptics.toggle()
                            }
                            doOpen()
                        }
                        .conditionalModifier(Defaults[.enableGestures]) { view in
                            view
                                .panGesture(direction: .down) { translation, phase in
                                    guard vm.notchState == .closed else { return }
                                    withAnimation(.smooth) {
                                        gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
                                    }
                                    
                                    if phase == .ended {
                                        withAnimation(.smooth) {
                                            gestureProgress = .zero
                                        }
                                    }
                                    if translation > Defaults[.gestureSensitivity] {
                                        if Defaults[.enableHaptics] {
                                            haptics.toggle()
                                        }
                                        withAnimation(.smooth) {
                                            gestureProgress = .zero
                                        }
                                        doOpen()
                                    }
                                }
                        }
                }
                .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                    view
                        .panGesture(direction: .up) { translation, phase in
                            if vm.notchState == .open {
                                withAnimation(.smooth) {
                                    gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
                                }
                                if phase == .ended {
                                    withAnimation(.smooth) {
                                        gestureProgress = .zero
                                    }
                                }
                                if translation > Defaults[.gestureSensitivity] {
                                    withAnimation(.smooth) {
                                        gestureProgress = .zero
                                        hoverAnimation = false
                                    }
                                    vm.close()
                                    if (vm.notchState == .closed) && Defaults[.enableHaptics] {
                                        haptics.toggle()
                                    }
                                }
                            }
                        }
                }
                .onAppear(perform: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        withAnimation(vm.animation) {
                            if coordinator.firstLaunch {
                                doOpen()
                            }
                        }
                    }
                })
                .sensoryFeedback(.alignment, trigger: haptics)
                .contextMenu {
                    SettingsLink(label: {
                        Text("Settings")
                    })
                    .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                    Button("Edit") {
                        let dn = DynamicNotch(content: EditPanelView())
                        dn.toggle()
                    }
#if DEBUG
                    .disabled(false)
#else
                    .disabled(true)
#endif
                    .keyboardShortcut("E", modifiers: .command)
                }
        }
        .frame(maxWidth: openNotchSize.width + 40, maxHeight: openNotchSize.height + 20, alignment: .top)
        .shadow(color: ((vm.notchState == .open || hoverAnimation) && Defaults[.enableShadow]) ? .black.opacity(0.6) : .clear, radius: Defaults[.cornerRadiusScaling] ? 10 : 5)
        .background(dragDetector)
        .environmentObject(vm)
        .environmentObject(batteryModel)
        .environmentObject(musicManager)
        .environmentObject(webcamManager)
    }
    
    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.firstLaunch {
                    Spacer()
                    HelloAnimation().frame(width: 200, height: 80).onAppear(perform: {
                        vm.closeHello()
                    })
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if vm.expandingView.type == .battery && vm.expandingView.show && vm.notchState == .closed {
                        HStack(spacing: 0) {
                            HStack {
                                Text("Charging")
                                    .font(.subheadline)
                            }
                            
                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 5)
                            
                            HStack {
                                BoringBatteryView(
                                    batteryPercentage: batteryModel.batteryPercentage, isPluggedIn: batteryModel.isPluggedIn,
                                    batteryWidth: 30,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.closedNotchSize.height + (hoverAnimation ? 8 : 0), alignment: .center)
                    } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) {
                        InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $hoverAnimation, gestureProgress: $gestureProgress)
                            .transition(.opacity)
                    } else if !vm.expandingView.show && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.showMusicLiveActivityOnClosed {
                        MusicLiveActivity()
                    } else {
                        BoringHeader()
                            .frame(height: max(24, vm.closedNotchSize.height))
                            .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
                    }
                    
                    if coordinator.sneakPeek.show && !Defaults[.inlineHUD] {
                        if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) {
                            SystemEventIndicatorModifier(eventType: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, sendEventBack: { _ in
                                //
                            })
                            .padding(.bottom, 10)
                            .padding(.leading, 4)
                            .padding(.trailing, 8)
                        } else if coordinator.sneakPeek.type != .battery {
                            if vm.notchState == .closed {
                                HStack(alignment: .center) {
                                    Image(systemName: "music.note")
                                    GeometryReader { geo in
                                        MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName), textColor: .gray, minDuration: 1, frameWidth: geo.size.width)
                                    }
                                }
                                .foregroundStyle(.gray)
                                .padding(.bottom, 10)
                            }
                        }
                    }
                }
            }
            .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (musicManager.isPlaying || !musicManager.isPlayerIdle))) { view in
                view
                    .fixedSize()
            }
            .zIndex(2)
            
            ZStack {
                if vm.notchState == .open {
                    switch coordinator.currentView {
                        case .home:
                            NotchHomeView(albumArtNamespace: albumArtNamespace)
                        case .shelf:
                            NotchShelfView()
                    }
                }
            }
            .zIndex(1)
            .allowsHitTesting(vm.notchState == .open)
            .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
            .opacity(abs(gestureProgress) > 0.3 ? min(abs(gestureProgress * 2), 0.8) : 1)
        }
    }
    
    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            HStack {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .background(
                        Image(nsImage: musicManager.albumArt)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed))
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                    .frame(width: max(0, vm.closedNotchSize.height - 12), height: max(0, vm.closedNotchSize.height - 12))
            }
            .frame(width: max(0, vm.closedNotchSize.height - (hoverAnimation ? 0 : 12) + gestureProgress / 2), height: max(0, vm.closedNotchSize.height - (hoverAnimation ? 0 : 12)))
            
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)
            
            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor).gradient : Color.gray.gradient)
                        .mask {
                            AudioSpectrumView(
                                isPlaying: $musicManager.isPlaying
                            )
                            .frame(width: 16, height: 12)
                        }
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                } else {
                    LottieAnimationView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: max(0, vm.closedNotchSize.height - (hoverAnimation ? 0 : 12) + gestureProgress / 2),
                   height:  max(0,vm.closedNotchSize.height - (hoverAnimation ? 0 : 12)), alignment: .center)
        }
        .frame(height: vm.closedNotchSize.height + (hoverAnimation ? 8 : 0), alignment: .center)
    }
    
    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.data], isTargeted: $vm.dragDetectorTargeting) { _ in true }
                .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
                    if isTargeted, vm.notchState == .closed {
                        coordinator.currentView = .shelf
                        doOpen()
                    } else if !isTargeted {
                        print("DROP EVENT", vm.dropEvent)
                        if vm.dropEvent {
                            vm.dropEvent = false
                            return
                        }
                        
                        vm.dropEvent = false
                        vm.close()
                    }
                }
        } else {
            EmptyView()
        }
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
    
    private func doOpen() {
        vm.open()
        cancelHoverTimer()
    }
    
    private func checkHoverDuration() {
        guard let startTime = hoverStartTime else { return }
        let hoverDuration = Date().timeIntervalSince(startTime)
        if hoverDuration >= Defaults[.minimumHoverDuration] {
            doOpen()
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

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void
    
    func dropEntered(info: DropInfo) {
        isTargeted = true
    }
    
    func dropExited(info: DropInfo) {
        isTargeted = false
    }
    
    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }
}
