//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var batteryModel: BatteryStatusViewModel
    @EnvironmentObject var musicManager: MusicManager
    @StateObject var webcamManager: WebcamManager = .init()

    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @State private var hoverStartTime: Date?
    @State private var isHovering: Bool = false
    @State private var hoverAnimation: Bool = false
    @State private var hoverTask: DispatchWorkItem?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.useModernCloseAnimation) var useModernCloseAnimation

    var body: some View {
        ZStack(alignment: .top) {
            NotchLayout()
                .frame(alignment: .top)
                .padding(.horizontal, vm.notchState == .open ? Defaults[.cornerRadiusScaling] ? (cornerRadiusInsets.opened - 5) : (cornerRadiusInsets.closed - 5) : 12)
                .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                .background(.black)
                .mask {
                    NotchShape(cornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling]) ? cornerRadiusInsets.opened : cornerRadiusInsets.closed).drawingGroup()
                }
                .padding(.bottom, vm.notchState == .open ? 30 : 0) // Safe area to ensure the notch does not close if the cursor is within 30px of the notch from the bottom.
                .conditionalModifier(!useModernCloseAnimation) { view in
                            let notchStateAnimation = Animation.bouncy.speed(1.2)
                            let hoverAnimationAnimation = Animation.bouncy.speed(1.2)
                            return view
                                .animation(notchStateAnimation, value: vm.notchState)
                                .animation(hoverAnimationAnimation, value: hoverAnimation)
                        }
                .conditionalModifier(useModernCloseAnimation) { view in
                    let hoverAnimationAnimation = Animation.bouncy.speed(1.2)
                    let notchStateAnimation = Animation.spring.speed(1.2)
                    return view
                        .animation(hoverAnimationAnimation, value: hoverAnimation)
                        .animation(notchStateAnimation, value: vm.notchState)
                }
                .allowsHitTesting(true)
                .animation(.smooth, value: gestureProgress)
                .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
                .conditionalModifier(Defaults[.openNotchOnHover]) { view in
                    view.onHover { systemHovering in
                        let hovering = systemHovering || vm.isMouseHovering()

                        if hovering {
                            // Use Core Animation for hover state
                            withAnimation(.bouncy.speed(1.2)) {
                                hoverAnimation = true
                                isHovering = true
                            }

                            if (vm.notchState == .closed) && Defaults[.enableHaptics] {
                                haptics.toggle()
                            }

                            if coordinator.sneakPeek.show {
                                return
                            }

                            hoverTask?.cancel()

                            let task = DispatchWorkItem { [weak vm] in
                                guard let vm = vm, vm.notchState == .closed else { return }
                                DispatchQueue.main.async {
                                    withAnimation(.bouncy.speed(1.2)) {
                                        doOpen()
                                    }
                                }
                            }

                            hoverTask = task
                            DispatchQueue.main.asyncAfter(deadline: .now() + Defaults[.minimumHoverDuration], execute: task)

                        } else {
                            hoverTask?.cancel()
                            hoverTask = nil

                            // Use Core Animation for hover exit
                            withAnimation(.bouncy.speed(1.2)) {
                                hoverAnimation = false
                                isHovering = false
                            }

                            if vm.notchState == .open {
                                withAnimation(.bouncy.speed(1.2)) {
                                    vm.close()
                                }
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
        .frame(maxWidth: openNotchSize.width, maxHeight: openNotchSize.height, alignment: .top)
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
                    .padding(.top, 40).padding(.leading, 100).padding(.trailing, 100)
                    Spacer().animation(.spring(.bouncy(duration: 0.4)), value: coordinator.firstLaunch)
                } else {
                    if vm.expandingView.type == .battery && vm.expandingView.show && vm.notchState == .closed {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.isInitialPlugIn ? "Plugged In" : "Charging")
                                    .font(.subheadline)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 5)

                            HStack {
                                BoringBatteryView(
                                    batteryPercentage: batteryModel.batteryPercentage, 
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    batteryWidth: 30,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isInitialPlugIn: batteryModel.isInitialPlugIn
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.closedNotchSize.height + (hoverAnimation ? 8 : 0), alignment: .center)
                    } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (vm.expandingView.type != .battery) {
                        InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $hoverAnimation, gestureProgress: $gestureProgress)
                            .transition(.opacity)
                    } else if !vm.expandingView.show && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.showMusicLiveActivityOnClosed {
                        MusicLiveActivity()
                    } else if !vm.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] {
                        BoringFaceAnimation().animation(.interactiveSpring, value: musicManager.isPlayerIdle)
                    } else if vm.notchState == .open {
                        BoringHeader()
                            .frame(height: max(24, vm.closedNotchSize.height))
                            .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
                            .animation(.spring(response: 1, dampingFraction: 1, blendDuration: 0.8), value: vm.notchState)
                    } else {
                        Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.closedNotchSize.height)
                    }

                    if coordinator.sneakPeek.show && !Defaults[.inlineHUD] {
                        if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) {
                            SystemEventIndicatorModifier(eventType: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, sendEventBack: { _ in
                                //
                            })
                            .padding(.bottom, 10)
                            .padding(.leading, 4)
                            .padding(.trailing, 8)
                        } else if vm.expandingView.type != .battery {
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
    func BoringFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(width: max(0, vm.closedNotchSize.height - 12), height: max(0, vm.closedNotchSize.height - 12))
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(height: vm.closedNotchSize.height + (hoverAnimation ? 8 : 0), alignment: .center)
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
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                        .frame(width: max(0, vm.closedNotchSize.height - (hoverAnimation ? 0 : 12) + gestureProgress / 2),
                               height: max(0, vm.closedNotchSize.height - (hoverAnimation ? 0 : 12)), alignment: .center)
                } else {
                    LottieAnimationView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: max(0, vm.closedNotchSize.height - (hoverAnimation ? 0 : 12) + gestureProgress / 2),
                   height: max(0, vm.closedNotchSize.height - (hoverAnimation ? 0 : 12)), alignment: .center)
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

    private func doOpen() {
        withAnimation(.bouncy.speed(1.2)) {
            vm.open()
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }
}
