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
    @StateObject var webcamManager: WebcamManager = .init()

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared

    @State private var isHovering: Bool = false
    @State private var hoverWorkItem: DispatchWorkItem?
    @State private var debounceWorkItem: DispatchWorkItem?
    
    @State private var isHoverStateChanging: Bool = false

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
                //.padding(.bottom, vm.notchState == .open ? 30 : 0) // Safe area to ensure the notch does not close if the cursor is within 30px of the notch from the bottom.

                .conditionalModifier(!useModernCloseAnimation) { view in
                    let hoverAnimationAnimation = Animation.bouncy.speed(1.2)
                    let notchStateAnimation = Animation.spring.speed(1.2)
                        return view
                            .animation(hoverAnimationAnimation, value: isHovering)
                            .animation(notchStateAnimation, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                            .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
                        }
                .conditionalModifier(useModernCloseAnimation) { view in
                    let hoverAnimationAnimation = Animation.bouncy.speed(1.2)
                    let notchStateAnimation = Animation.spring.speed(1.2)
                    return view
                        .animation(hoverAnimationAnimation, value: isHovering)
                        .animation(notchStateAnimation, value: vm.notchState)
                }
                .conditionalModifier(Defaults[.openNotchOnHover]) { view in
                    view.onHover { hovering in
                        handleHover(hovering)
                    }
                }
                .conditionalModifier(!Defaults[.openNotchOnHover]) { view in
                    view
                        .onHover { hovering in
                            withAnimation(vm.animation) {
                                isHovering = hovering
                            }
                            
                            // Only close if mouse leaves and the notch is open
                            if !hovering && vm.notchState == .open {
                                vm.close()
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
                                    handleDownGesture(translation: translation, phase: phase)
                                }
                        }
                }
                .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                    view
                        .panGesture(direction: .up) { translation, phase in
                            handleUpGesture(translation: translation, phase: phase)
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
                .onChange(of: vm.notchState) { _, newState in
                    // Reset hover state when notch state changes
                    if newState == .closed && isHovering {
                        // Only reset visually, without triggering the hover logic again
                        isHoverStateChanging = true
                        withAnimation {
                            isHovering = false
                        }
                        // Reset the flag after the animation completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isHoverStateChanging = false
                        }
                    }
                }
                .sensoryFeedback(.alignment, trigger: haptics)
                .contextMenu {
                    SettingsLink(label: {
                        Text("Settings")
                    })
                    .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
//                    Button("Edit") { // Doesnt work....
//                        let dn = DynamicNotch(content: EditPanelView())
//                        dn.toggle()
//                    }
//                    #if DEBUG
//                    .disabled(false)
//                    #else
//                    .disabled(true)
//                    #endif
//                    .keyboardShortcut("E", modifiers: .command)
                }
        }
        .frame(maxWidth: openNotchSize.width, maxHeight: openNotchSize.height, alignment: .top)
        .shadow(color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow]) ? .black.opacity(0.6) : .clear, radius: Defaults[.cornerRadiusScaling] ? 10 : 5)
        .background(dragDetector)
        .environmentObject(vm)
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
                      if coordinator.expandingView.type == .battery && coordinator.expandingView.show && vm.notchState == .closed && Defaults[.showPowerStatusNotifications] {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 5)

                            HStack {
                                BoringBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.closedNotchSize.height + (isHovering ? 8 : 0), alignment: .center)
                      } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          MusicLiveActivity()
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation().animation(.interactiveSpring, value: musicManager.isPlayerIdle)
                      } else if vm.notchState == .open {
                          BoringHeader()
                              .frame(height: max(24, vm.closedNotchSize.height))
                              .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
                              .animation(.spring(response: 1, dampingFraction: 1, blendDuration: 0.8), value: vm.notchState)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.closedNotchSize.height)
                       }
                      
                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] {
                              SystemEventIndicatorModifier(eventType: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, sendEventBack: { _ in
                                  //
                              })
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
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
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
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
        }.frame(height: vm.closedNotchSize.height + (isHovering ? 8 : 0), alignment: .center)
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
            .frame(width: max(0, vm.closedNotchSize.height - (isHovering ? 0 : 12) + gestureProgress / 2), height: max(0, vm.closedNotchSize.height - (isHovering ? 0 : 12)))

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top){
                        if(coordinator.expandingView.show && coordinator.expandingView.type == .music) {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity((coordinator.expandingView.show && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray)
                                .opacity((coordinator.expandingView.show && coordinator.expandingView.type == .music && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                        }
                    }
                )
                .frame(width: (coordinator.expandingView.show && coordinator.expandingView.type == .music && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 380 : vm.closedNotchSize.width + (isHovering ? 8 : 0))
            

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
                        .frame(width: max(0, vm.closedNotchSize.height - (isHovering ? 0 : 12) + gestureProgress / 2),
                               height: max(0, vm.closedNotchSize.height - (isHovering ? 0 : 12)), alignment: .center)
                } else {
                    LottieAnimationView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: max(0, vm.closedNotchSize.height - (isHovering ? 0 : 12) + gestureProgress / 2),
                   height: max(0, vm.closedNotchSize.height - (isHovering ? 0 : 12)), alignment: .center)
        }
        .frame(height: vm.closedNotchSize.height + (isHovering ? 8 : 0), alignment: .center)
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

    private func calculateBottomPadding() -> CGFloat {
		let safeAreaNotchHeight: CGFloat = 30 // Safe area to ensure the notch does not close if the cursor is within 30px of the notch from the bottom.
		
        if vm.notchState == .open {
            return safeAreaNotchHeight
        }
        
        let shouldExtendHover = vm.closedNotchSize.height == 0 && Defaults[.extendHoverArea]
        return shouldExtendHover ? safeAreaNotchHeight : 0
    }

    // MARK: - Hover Management
    
    /// Handle hover state changes with debouncing
    private func handleHover(_ hovering: Bool) {
        // Don't process events if we're already transitioning
        if isHoverStateChanging { return }
        
        // Cancel any pending tasks
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        
        if hovering {
            // Handle mouse enter
            withAnimation(.bouncy.speed(1.2)) {
                isHovering = true
            }
            
            // Only provide haptic feedback if notch is closed
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            // Don't open notch if there's a sneak peek showing
            if coordinator.sneakPeek.show {
                return
            }
            
            // Delay opening the notch
            let task = DispatchWorkItem {
                // ContentView is a struct, so we don't use weak self here
                guard vm.notchState == .closed, isHovering else { return }
                doOpen()
            }
            
            hoverWorkItem = task
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Defaults[.minimumHoverDuration],
                execute: task
            )
        } else {
            // Handle mouse exit with debounce to prevent flickering
            let debounce = DispatchWorkItem {
                // ContentView is a struct, so we don't use weak self here
                
                // Update visual state
                withAnimation(.bouncy.speed(1.2)) {
                    isHovering = false
                }
                
                // Close the notch if it's open
                if vm.notchState == .open {
                    vm.close()
                }
            }
            
            debounceWorkItem = debounce
            // Add a small delay to debounce rapid mouse movements
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: debounce)
        }
    }
    
    // MARK: - Gesture Handling
    
    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
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
    
    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        if vm.notchState == .open && !vm.isHoveringCalendar {
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
                    isHovering = false
                }
                vm.close()
                
                if Defaults[.enableHaptics] {
                    haptics.toggle()
                }
            }
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
