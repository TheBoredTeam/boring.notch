//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//  Actualizado por integración Plex (dos columnas) el 30/10/2025
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

// MARK: - ContentView

struct ContentView: View {
    // Core VMs
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var coordinator  = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared

    // Plex enricher
    @ObservedObject private var plexVM = PlexNowPlayingViewModel.shared

    // UI State
    @State private var isHovering: Bool = false
    @State private var hoverWorkItem: DispatchWorkItem?
    @State private var debounceWorkItem: DispatchWorkItem?
    @State private var isHoverStateChanging: Bool = false
    @State private var gestureProgress: CGFloat = .zero
    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    // Defaults
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.showNotHumanFace)   var showNotHumanFace
    @Default(.useModernCloseAnimation) var useModernCloseAnimation

    // Layout tweaks
    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    // MARK: Body

    var body: some View {
        rootBody()
            .padding(.bottom, 8)
            .frame(maxWidth: openNotchSize.width,
                   maxHeight: openNotchSize.height,
                   alignment: .top)
            .shadow(
                color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                ? .black.opacity(0.2) : .clear,
                radius: Defaults[.cornerRadiusScaling] ? 6 : 4
            )
            .background(dragDetector)
            .environmentObject(vm)
    }

    // MARK: break-down body

    @ViewBuilder
    private func rootBody() -> some View {
        ZStack(alignment: .top) {
            buildMainLayout()
        }
    }

    // MARK: - Build main layout

    private func buildMainLayout() -> some View {
        let base = NotchLayout()
            .frame(alignment: .top)
            .padding(
                .horizontal,
                vm.notchState == .open
                ? (Defaults[.cornerRadiusScaling]
                   ? (cornerRadiusInsets.opened.top)
                   : (cornerRadiusInsets.opened.bottom))
                : cornerRadiusInsets.closed.bottom
            )
            .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
            .background(Color.black)
            .mask(
                (vm.notchState == .open && Defaults[.cornerRadiusScaling])
                ? AnyView(NotchShape(
                    topCornerRadius: cornerRadiusInsets.opened.top,
                    bottomCornerRadius: cornerRadiusInsets.opened.bottom
                ).drawingGroup())
                : AnyView(NotchShape(
                    topCornerRadius: cornerRadiusInsets.closed.top,
                    bottomCornerRadius: cornerRadiusInsets.closed.bottom
                ).drawingGroup())
            )
            .padding(
                .bottom,
                vm.notchState == .open && Defaults[.extendHoverArea]
                ? 0
                : (vm.effectiveClosedNotchHeight == 0 ? zeroHeightHoverPadding : 0)
            )

        return base
            .animation(.bouncy.speed(1.2), value: isHovering)
            .animation(.spring.speed(1.2), value: vm.notchState)
            .animation(.smooth, value: gestureProgress)
            .modifier(
                HoverOrTapModifier(
                    isModernClose: useModernCloseAnimation,
                    isHovering: $isHovering,
                    isOpen: { vm.notchState == .open },
                    open: { vm.open() },
                    close: { vm.close() },
                    enableHaptics: Defaults[.enableHaptics],
                    enableGestures: Defaults[.enableGestures],
                    doOpen: { doOpen() },
                    handleDown: { translation, phase in
                        handleDownGesture(translation: translation, phase: phase)
                    },
                    handleUp: { translation, phase in
                        handleUpGesture(translation: translation, phase: phase)
                    },
                    onHoverChange: { hovering in
                        handleHover(hovering)
                    }
                )
            )
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    withAnimation(vm.animation) {
                        if coordinator.firstLaunch { doOpen() }
                    }
                }
            }
            .onChange(of: vm.notchState) { _, newState in
                if newState == .closed && isHovering {
                    isHoverStateChanging = true
                    withAnimation { isHovering = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isHoverStateChanging = false
                    }
                }
            }
            .onChange(of: vm.isBatteryPopoverActive) { _, newPopoverState in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !newPopoverState && !isHovering && vm.notchState == .open {
                        vm.close()
                    }
                }
            }
            .sensoryFeedback(.alignment, trigger: haptics)
            .contextMenu {
                Button("Settings") { SettingsWindowController.shared.showWindow() }
                    .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            }
    }

    // MARK: - NotchLayout (contenido)

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {

            // Header/mini-cabecera o placeholders
            VStack(alignment: .leading) {
                if coordinator.firstLaunch {
                    Spacer()
                    HelloAnimation()
                        .frame(width: 200, height: 80)
                        .onAppear { vm.closeHello()
                            // 🟢 Arranque automático del poller Plex
                            if
                                let pmsStr = UserDefaults.standard.string(forKey: "PMS_URL"),
                                let pms = URL(string: pmsStr),
                                let token = UserDefaults.standard.string(forKey: "PLEX_TOKEN"),
                                !token.isEmpty
                            {
                                print("🧭 [ContentView] Iniciando poller automático")
                                PlexNowPlayingViewModel.shared.startPlexPolling(baseURL: pms, token: token)
                            } else {
                                print("⚠️ [ContentView] Falta PMS_URL o PLEX_TOKEN en UserDefaults")
                            }
                            
                        }
                        .padding(.top, 40)
                    Spacer()
                } else {
                    if coordinator.expandingView.type == .battery &&
                        coordinator.expandingView.show &&
                        vm.notchState == .closed &&
                        Defaults[.showPowerStatusNotifications] {

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
                        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0),
                               alignment: .center)

                    } else if coordinator.sneakPeek.show &&
                                Defaults[.inlineHUD] &&
                                (coordinator.sneakPeek.type != .music) &&
                                (coordinator.sneakPeek.type != .battery) {
                        InlineHUD(
                            type: $coordinator.sneakPeek.type,
                            value: $coordinator.sneakPeek.value,
                            icon:  $coordinator.sneakPeek.icon,
                            hoverAnimation: $isHovering,
                            gestureProgress: $gestureProgress
                        )
                        .transition(.opacity)

                    } else if (!coordinator.expandingView.show ||
                               coordinator.expandingView.type == .music) &&
                                vm.notchState == .closed &&
                                (musicManager.isPlaying || !musicManager.isPlayerIdle) &&
                                coordinator.musicLiveActivityEnabled &&
                                !vm.hideOnClosed {
                        MusicLiveActivity()

                    } else if !coordinator.expandingView.show &&
                                vm.notchState == .closed &&
                                (!musicManager.isPlaying && musicManager.isPlayerIdle) &&
                                Defaults[.showNotHumanFace] &&
                                !vm.hideOnClosed {
                        BoringFaceAnimation()
                            .animation(.interactiveSpring, value: musicManager.isPlayerIdle)

                    } else if vm.notchState == .open {
                        BoringHeader()
                            .frame(height: max(24, vm.effectiveClosedNotchHeight))
                            .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
                            .animation(.spring(response: 1,
                                               dampingFraction: 1,
                                               blendDuration: 0.8),
                                       value: vm.notchState)
                    } else {
                        Rectangle()
                            .fill(.clear)
                            .frame(width: vm.closedNotchSize.width - 20,
                                   height: vm.effectiveClosedNotchHeight)
                    }

                    if coordinator.sneakPeek.show {
                        if (coordinator.sneakPeek.type != .music) &&
                            (coordinator.sneakPeek.type != .battery) &&
                            !Defaults[.inlineHUD] {
                            SystemEventIndicatorModifier(
                                eventType: $coordinator.sneakPeek.type,
                                value: $coordinator.sneakPeek.value,
                                icon:  $coordinator.sneakPeek.icon,
                                sendEventBack: { _ in }
                            )
                            .padding(.bottom, 10)
                            .padding(.leading, 4)
                            .padding(.trailing, 8)
                        } else if coordinator.sneakPeek.type == .music {
                            if vm.notchState == .closed &&
                                !vm.hideOnClosed &&
                                Defaults[.sneakPeekStyles] == .standard {
                                HStack(alignment: .center) {
                                    Image(systemName: "music.note")
                                    GeometryReader { geo in
                                        MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),
                                                    textColor: Defaults[.playerColorTinting]
                                                    ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                                                    : .gray,
                                                    minDuration: 1,
                                                    frameWidth: geo.size.width)
                                    }
                                }
                                .foregroundStyle(.gray)
                                .padding(.bottom, 10)
                            }
                        }
                    }
                }
            }
            .conditionalModifier(
                (coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) &&
                 vm.notchState == .closed && !vm.hideOnClosed &&
                 Defaults[.sneakPeekStyles] == .standard) ||
                (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) &&
                 (vm.notchState == .closed))
            ) { view in
                view.fixedSize()
            }
            .zIndex(2)

            // Contenido principal (dos columnas)
            ZStack {
                if vm.notchState == .open {
                    switch coordinator.currentView {
                    case .home:
                        HStack(alignment: .top, spacing: 16) {
                            // IZQUIERDA
                            NotchHomeView(albumArtNamespace: albumArtNamespace)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // DERECHA: Facts del VM
                            Group {
                                switch plexVM.state {
                                case .ready:
                                    PlexNowPlayingFactsView()
                                case .loading, .idle:
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Cargando…")
                                            .foregroundStyle(.secondary)
                                    }
                                case .error(let message):
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Error")
                                            .foregroundStyle(.secondary)
                                        Text(message)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.leading, 6)
                            .padding(.trailing, 8)
                            .padding(.bottom, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 5)

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

    // MARK: - Subvistas utilitarias

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
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0),
               alignment: .center)
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
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed
                        )
                    )
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
            }
            .frame(
                width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
                height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
            )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show && coordinator.expandingView.type == .music {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor)
                                : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show &&
                                 Defaults[.enableSneakPeek] &&
                                 Defaults[.sneakPeekStyles] == .inline) ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor)
                                    : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show &&
                                     coordinator.expandingView.type == .music &&
                                     Defaults[.enableSneakPeek] &&
                                     Defaults[.sneakPeekStyles] == .inline) ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show &&
                            coordinator.expandingView.type == .music &&
                            Defaults[.enableSneakPeek] &&
                            Defaults[.sneakPeekStyles] == .inline)
                    ? 380
                    : vm.closedNotchSize.width + (isHovering ? 8 : 0)
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
                        .frame(
                            width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
                            height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)),
                            alignment: .center
                        )
                } else {
                    LottieAnimationView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
                height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)),
                alignment: .center
            )
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
    }

    // MARK: - Drag detector (drop)

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

    // MARK: - Actions

    private func doOpen() {
        withAnimation(.bouncy.speed(1.2)) { vm.open() }
    }

    private func handleHover(_ hovering: Bool) {
        if isHoverStateChanging { return }

        hoverWorkItem?.cancel(); hoverWorkItem = nil
        debounceWorkItem?.cancel(); debounceWorkItem = nil

        if hovering {
            withAnimation(.bouncy.speed(1.2)) { isHovering = true }
            if vm.notchState == .closed && Defaults[.enableHaptics] { haptics.toggle() }
            if coordinator.sneakPeek.show { return }

            let task = DispatchWorkItem {
                guard vm.notchState == .closed, isHovering else { return }
                doOpen()
            }
            hoverWorkItem = task
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Defaults[.minimumHoverDuration],
                execute: task
            )
        } else {
            let debounce = DispatchWorkItem {
                withAnimation(.bouncy.speed(1.2)) { isHovering = false }
                if vm.notchState == .open && !vm.isBatteryPopoverActive { vm.close() }
            }
            debounceWorkItem = debounce
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: debounce)
        }
    }

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }
        withAnimation(.smooth) { gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20 }
        if phase == .ended { withAnimation(.smooth) { gestureProgress = .zero } }
        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] { haptics.toggle() }
            withAnimation(.smooth) { gestureProgress = .zero }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        if vm.notchState == .open && !vm.isHoveringCalendar {
            withAnimation(.smooth) { gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20 }
            if phase == .ended { withAnimation(.smooth) { gestureProgress = .zero } }
            if translation > Defaults[.gestureSensitivity] {
                withAnimation(.smooth) {
                    gestureProgress = .zero
                    isHovering = false
                }
                vm.close()
                if Defaults[.enableHaptics] { haptics.toggle() }
            }
        }
    }
}

// MARK: - HoverOrTapModifier (sin NotchState acoplado) — con type erasure

private struct HoverOrTapModifier: ViewModifier {
    let isModernClose: Bool
    @Binding var isHovering: Bool

    let isOpen: () -> Bool
    let open:  () -> Void
    let close: () -> Void

    let enableHaptics: Bool
    let enableGestures: Bool
    let doOpen: () -> Void
    let handleDown: (CGFloat, NSEvent.Phase) -> Void
    let handleUp:   (CGFloat, NSEvent.Phase) -> Void
    let onHoverChange: (Bool) -> Void

    func body(content: Content) -> some View {
        // ⛑️ Erase type to avoid "Cannot assign value of type 'some View' to 'Content'"
        var erased: AnyView = AnyView(content)

        erased = AnyView(
            erased.onHover { hovering in
                onHoverChange(hovering)
            }
        )

        erased = AnyView(
            erased.onTapGesture {
                doOpen()
            }
        )

        if enableGestures {
            erased = AnyView(
                erased.panGesture(direction: .down) { translation, phase in
                    handleDown(translation, phase)
                }
            )
        }

        if Defaults[.closeGestureEnabled] && enableGestures {
            erased = AnyView(
                erased.panGesture(direction: .up) { translation, phase in
                    handleUp(translation, phase)
                }
            )
        }

        return erased
    }
}

// MARK: - Preview

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
