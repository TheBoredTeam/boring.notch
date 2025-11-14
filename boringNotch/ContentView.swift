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

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared

    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.useModernCloseAnimation) var useModernCloseAnimation

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    var body: some View {
        ZStack(alignment: .top) {
            let mainLayout = NotchLayout()
                .frame(alignment: .top)
                .padding(
                    .horizontal,
                    vm.notchState == .open
                        ? Defaults[.cornerRadiusScaling]
                            ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                )
                .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                .background(.black)
                .mask {
                    ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                        ? NotchShape(
                            topCornerRadius: cornerRadiusInsets.opened.top,
                            bottomCornerRadius: cornerRadiusInsets.opened.bottom
                        )
                        : NotchShape(
                            topCornerRadius: cornerRadiusInsets.closed.top,
                            bottomCornerRadius: cornerRadiusInsets.closed.bottom
                        )
                }
                .padding(
                    .bottom,
                    vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                )

            mainLayout
                .conditionalModifier(!useModernCloseAnimation) { view in
                    let hoverAnimationAnimation = Animation.bouncy.speed(1.2)
                    let notchStateAnimation = Animation.spring.speed(1.2)
                    return
                        view
                        .animation(hoverAnimationAnimation, value: isHovering)
                        .animation(notchStateAnimation, value: vm.notchState)
                        .animation(.smooth, value: gestureProgress)
                        .transition(
                            .blurReplace.animation(
                                .interactiveSpring(dampingFraction: 1.2)
                            )
                        )
                }
                .conditionalModifier(useModernCloseAnimation) { view in
                    let notchStateAnimation = Animation.spring.speed(1.2)
                    return view
                        .animation(notchStateAnimation, value: vm.notchState)
                        .animation(.smooth, value: gestureProgress)
                }
                .onHover { hovering in
                    handleHover(hovering)
                }
                .onTapGesture {
                    doOpen()
                }
                .conditionalModifier(Defaults[.enableGestures]) { view in
                    view
                        .panGesture(direction: .down) { translation, phase in
                            handleDownGesture(translation: translation, phase: phase)
                        }
                }
                .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                    view
                        .panGesture(direction: .up) { translation, phase in
                            handleUpGesture(translation: translation, phase: phase)
                        }
                }
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        await MainActor.run {
                            if coordinator.firstLaunch {
                                withAnimation(vm.animation) {
                                    doOpen()
                                }
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                    if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                        hoverTask?.cancel()
                        hoverTask = Task {
                            try? await Task.sleep(for: .milliseconds(100))
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                    self.vm.close()
                                }
                            }
                        }
                    }
                }
                .onChange(of: vm.notchState) { _, newState in
                    if newState == .closed && isHovering {
                        withAnimation {
                            isHovering = false
                        }
                    }
                }
                .onChange(of: vm.isBatteryPopoverActive) {
                    if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                        hoverTask?.cancel()
                        hoverTask = Task {
                            try? await Task.sleep(for: .milliseconds(100))
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                    self.vm.close()
                                }
                            }
                        }
                    }
                }
                .sensoryFeedback(.alignment, trigger: haptics)
                .contextMenu {
                    Button("Settings") {
                        SettingsWindowController.shared.showWindow()
                    }
                    .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
//                    Button("Edit") { // Doesnt work....
//                        let dn = DynamicNotch(content: EditPanelView())
//                        dn.toggle()
//                    }
//                    .keyboardShortcut("E", modifiers: .command)
                }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: openNotchSize.width, maxHeight: openNotchSize.height, alignment: .top)
        .shadow(
            color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                ? .black.opacity(0.5) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
        )
        .background(dragDetector)
        .environmentObject(vm)
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.firstLaunch {
                    Spacer()
                    HelloAnimation().frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    ).onAppear(perform: {
                        vm.closeHello()
                    })
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                    {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 10)

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
                        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
                      } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && vm.notchState == .closed {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          MusicLiveActivity()
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .recording) && vm.notchState == .closed && (recordingManager.isRecording || !recordingManager.isRecorderIdle) && Defaults[.enableScreenRecordingDetection] && !vm.hideOnClosed {
                          RecordingLiveActivity()
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation()
                      } else if vm.notchState == .open {
                          BoringHeader()
                              .frame(height: max(24, vm.effectiveClosedNotchHeight))
                              .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
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
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
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
                        ShelfView()
                    }
                }
            }
            .zIndex(1)
            .allowsHitTesting(vm.notchState == .open)
            .blur(
                radius: abs(gestureProgress) > 0.3
                    ? min(abs(gestureProgress), 8) : 0
            )
            .opacity(
                abs(gestureProgress) > 0.3
                    ? min(abs(gestureProgress * 2), 0.8) : 1
            )
        }
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0),
            alignment: .center
        )
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380
                        : vm.closedNotchSize.width
                            + (isHovering ? 8 : -cornerRadiusInsets.closed.top)
                )

            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(
                            Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor).gradient
                                : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: max(
                    0,
                    vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)
                ),
                alignment: .center
            )
        }
        .frame(
            height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0),
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
                .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
                    anyDropDebounceTask?.cancel()

                    if isTargeted {
                        if vm.notchState == .closed {
                            coordinator.currentView = .shelf
                            doOpen()
                        }
                        return
                    }

                    anyDropDebounceTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }

                        if vm.dropEvent {
                            vm.dropEvent = false
                            return
                        }

                        vm.dropEvent = false
                        if !SharingStateManager.shared.preventNotchClose {
                            vm.close()
                        }
                    }
                }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open && !vm.isHoveringCalendar else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { vm.close() }

            if Defaults[.enableHaptics] {
                haptics.toggle()
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

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
