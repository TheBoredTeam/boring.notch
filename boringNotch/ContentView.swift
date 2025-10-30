//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//  Ajuste columnas fijas + centrado: 30/10/2025
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared

    // 🔹 ViewModel de Plex (enricher)
    @ObservedObject private var plexVM = PlexNowPlayingViewModel.shared

    // ⚙️ Config persistida (de tu ConfigView)
    @AppStorage("PMS_URL") private var pmsURL: String = "http://127.0.0.1:32400"
    @AppStorage("ENRICHER_URL") private var enricherURL: String = "http://127.0.0.1:5173"

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

    private let zeroHeightHoverPadding: CGFloat = 10

    var body: some View {
        ZStack(alignment: .top) {
            mainLayoutView
        }
        .padding(.bottom, 8)
        .frame(maxWidth: openNotchSize.width, maxHeight: openNotchSize.height, alignment: .top)
        .shadow(
            color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow]) ? .black.opacity(0.2) : .clear,
            radius: Defaults[.cornerRadiusScaling] ? 6 : 4
        )
        .background(dragDetector)
        .environmentObject(vm)
        // 🔻 Auto-inicio de polling Plex + Enricher
        .onAppear {
            if let token = KeychainStore.shared.loadToken(),
               let pms = URL(string: pmsURL),
               let enricher = URL(string: enricherURL) {
                plexVM.updateEnricher(baseURL: enricher)
                plexVM.startPlexPolling(baseURL: pms, token: token)
            } else {
                print("⚠️ Faltan PMS_URL o Token para iniciar polling automáticamente")
            }
        }
        .onChange(of: pmsURL) { _, newVal in
            if let token = KeychainStore.shared.loadToken(),
               let pms = URL(string: newVal) {
                plexVM.startPlexPolling(baseURL: pms, token: token)
            }
        }
        .onChange(of: enricherURL) { _, newVal in
            if let url = URL(string: newVal) {
                plexVM.updateEnricher(baseURL: url)
            }
        }
    }

    // MARK: - Secciones divididas para ayudar al type-checker

    private var mainLayoutView: some View {
        let base =
            NotchLayout()
                .frame(alignment: .top)
                .padding(
                    .horizontal,
                    vm.notchState == .open
                        ? (Defaults[.cornerRadiusScaling] ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom))
                        : cornerRadiusInsets.closed.bottom
                )
                .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                .background(.black)
                .mask {
                    ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                        ? NotchShape(topCornerRadius: cornerRadiusInsets.opened.top,
                                     bottomCornerRadius: cornerRadiusInsets.opened.bottom).drawingGroup()
                        : NotchShape(topCornerRadius: cornerRadiusInsets.closed.top,
                                     bottomCornerRadius: cornerRadiusInsets.closed.bottom).drawingGroup()
                }
                .padding(.bottom, vm.notchState == .open && Defaults[.extendHoverArea] ? 0 : (vm.effectiveClosedNotchHeight == 0 ? zeroHeightHoverPadding : 0))

        return base
            .modifier(AnimationsModifier(
                useModernCloseAnimation: useModernCloseAnimation,
                isHovering: $isHovering,
                isNotchOpen: vm.notchState == .open,
                gestureProgress: $gestureProgress
            ))
            .modifier(HoverGesturesModifier(
                openNotchOnHover: Defaults[.openNotchOnHover],
                enableGestures: Defaults[.enableGestures],
                closeGestureEnabled: Defaults[.closeGestureEnabled],
                isNotchClosed: vm.notchState == .closed,
                isHovering: $isHovering,
                haptics: $haptics,
                handleHover: handleHover(_:),
                handleDownGesture: handleDownGesture(translation:phase:),
                handleUpGesture: handleUpGesture(translation:phase:),
                doOpen: doOpen
            ))
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

    // MARK: - Contenido principal del Notch

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            headerArea
                .conditionalModifier(
                    (coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music)
                     && vm.notchState == .closed && !vm.hideOnClosed
                     && Defaults[.sneakPeekStyles] == .standard)
                    || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music)
                        && (vm.notchState == .closed))
                ) { view in
                    view.fixedSize()
                }
                .zIndex(2)

            ZStack {
                if vm.notchState == .open {
                    switch coordinator.currentView {
                    case .home:
                        GeometryReader { geo in
                            let w = geo.size.width
                            let spacing: CGFloat = 16
                            // proporción y límites: ancho estable del player
                            let leftWidth = max(min(w * 0.64, 560), 360)
                            let rightWidth = max(min(w * 0.36 - spacing, 420), 260)
                            let total = leftWidth + spacing + rightWidth

                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                HStack(alignment: .top, spacing: spacing) {
                                    // IZQ: Player (64%) – controles siempre visibles
                                    NotchHomeView(albumArtNamespace: albumArtNamespace)
                                        .frame(width: leftWidth, alignment: .leading)
                                        .clipped()
                                        .zIndex(1)

                                    // DER: Facts (36%)
                                    Group {
                                        switch plexVM.state {
                                        case .loaded, .loading, .idle:
                                            PlexNowPlayingFactsView()
                                        case .error(let message):
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("Error").foregroundStyle(.secondary)
                                                Text(message).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .frame(width: rightWidth, alignment: .topLeading)
                                }
                                .frame(width: total, alignment: .center)
                                Spacer(minLength: 0)
                            }
                            .frame(width: w) // 🔹 centra el conjunto en el ancho disponible
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

    // MARK: - Encabezado (idéntico al previo, condensado)

    @ViewBuilder
    private var headerArea: some View {
        VStack(alignment: .leading) {
            if coordinator.firstLaunch {
                Spacer()
                HelloAnimation()
                    .frame(width: 200, height: 80)
                    .onAppear { vm.closeHello() }
                    .padding(.top, 40)
                Spacer()
            } else {
                if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                    && vm.notchState == .closed && Defaults[.showPowerStatusNotifications] {

                    HStack(spacing: 0) {
                        HStack { Text(batteryModel.statusText).font(.subheadline).foregroundStyle(.white) }
                        Rectangle().fill(.black).frame(width: vm.closedNotchSize.width + 10)
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

                } else if coordinator.sneakPeek.show && Defaults[.inlineHUD]
                            && (coordinator.sneakPeek.type != .music)
                            && (coordinator.sneakPeek.type != .battery) {

                    InlineHUD(
                        type: $coordinator.sneakPeek.type,
                        value: $coordinator.sneakPeek.value,
                        icon: $coordinator.sneakPeek.icon,
                        hoverAnimation: $isHovering,
                        gestureProgress: $gestureProgress
                    )
                    .transition(.opacity)

                } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
                            && vm.notchState == .closed
                            && (musicManager.isPlaying || !musicManager.isPlayerIdle)
                            && coordinator.musicLiveActivityEnabled
                            && !vm.hideOnClosed {

                    MusicLiveActivity()

                } else if !coordinator.expandingView.show
                            && vm.notchState == .closed
                            && (!musicManager.isPlaying && musicManager.isPlayerIdle)
                            && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {

                    BoringFaceAnimation().animation(.interactiveSpring, value: musicManager.isPlayerIdle)

                } else if vm.notchState == .open {
                    BoringHeader()
                        .frame(height: max(24, vm.effectiveClosedNotchHeight))
                        .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
                        .animation(.spring(response: 1, dampingFraction: 1, blendDuration: 0.8), value: vm.notchState)
                } else {
                    Rectangle().fill(.clear)
                        .frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                }

                if coordinator.sneakPeek.show {
                    if (coordinator.sneakPeek.type != .music)
                        && (coordinator.sneakPeek.type != .battery)
                        && !Defaults[.inlineHUD] {

                        SystemEventIndicatorModifier(
                            eventType: $coordinator.sneakPeek.type,
                            value: $coordinator.sneakPeek.value,
                            icon: $coordinator.sneakPeek.icon,
                            sendEventBack: { _ in }
                        )
                        .padding(.bottom, 10)
                        .padding(.leading, 4)
                        .padding(.trailing, 8)

                    } else if coordinator.sneakPeek.type == .music {
                        if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                            HStack(alignment: .center) {
                                Image(systemName: "music.note")
                                GeometryReader { geo in
                                    MarqueeText(
                                        .constant(musicManager.songTitle + " - " + musicManager.artistName),
                                        textColor: Defaults[.playerColorTinting]
                                            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                                            : .gray,
                                        minDuration: 1,
                                        frameWidth: geo.size.width
                                    )
                                }
                            }
                            .foregroundStyle(.gray)
                            .padding(.bottom, 10)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subvistas auxiliares (igual que antes)

    @ViewBuilder
    func BoringFaceAnimation() -> some View { /* … igual que tu versión previa … */
        HStack {
            HStack {
                Rectangle().fill(.clear)
                    .frame(width: max(0, vm.effectiveClosedNotchHeight - 12),
                           height: max(0, vm.effectiveClosedNotchHeight - 12))
                Rectangle().fill(.black).frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View { /* … igual que tu versión previa … */
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
                    .frame(width: max(0, vm.effectiveClosedNotchHeight - 12),
                           height: max(0, vm.effectiveClosedNotchHeight - 12))
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
                                textColor: Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : .gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity((coordinator.expandingView.show
                                      && Defaults[.enableSneakPeek]
                                      && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                            Spacer(minLength: vm.closedNotchSize.width)
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : .gray)
                                .opacity((coordinator.expandingView.show
                                          && coordinator.expandingView.type == .music
                                          && Defaults[.enableSneakPeek]
                                          && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                            && Defaults[.enableSneakPeek]
                            && Defaults[.sneakPeekStyles] == .inline)
                        ? 380 : vm.closedNotchSize.width + (isHovering ? 8 : 0)
                )

            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(Defaults[.coloredSpectrogram]
                              ? Color(nsColor: musicManager.avgColor).gradient
                              : Color.gray.gradient)
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask { AudioSpectrumView(isPlaying: $musicManager.isPlaying).frame(width: 16, height: 12) }
                        .frame(
                            width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
                            height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)),
                            alignment: .center
                        )
                } else {
                    LottieAnimationView().frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Drag detector / acciones / hover / gestos (idénticos)

    @ViewBuilder
    var dragDetector: some View { /* … igual que antes … */
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
                        if vm.dropEvent { vm.dropEvent = false; return }
                        vm.dropEvent = false
                        vm.close()
                    }
                }
        } else {
            EmptyView()
        }
    }

    private func doOpen() { withAnimation(.bouncy.speed(1.2)) { vm.open() } }
    private func handleHover(_ hovering: Bool) { /* … igual que antes … */
        if isHoverStateChanging { return }
        hoverWorkItem?.cancel(); hoverWorkItem = nil
        debounceWorkItem?.cancel(); debounceWorkItem = nil
        if hovering {
            withAnimation(.bouncy.speed(1.2)) { isHovering = true }
            if vm.notchState == .closed && Defaults[.enableHaptics] { haptics.toggle() }
            if coordinator.sneakPeek.show { return }
            let task = DispatchWorkItem { guard vm.notchState == .closed, isHovering else { return }; doOpen() }
            hoverWorkItem = task
            DispatchQueue.main.asyncAfter(deadline: .now() + Defaults[.minimumHoverDuration], execute: task)
        } else {
            let debounce = DispatchWorkItem {
                withAnimation(.bouncy.speed(1.2)) { isHovering = false }
                if vm.notchState == .open && !vm.isBatteryPopoverActive { vm.close() }
            }
            debounceWorkItem = debounce
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: debounce)
        }
    }
    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) { /* … igual … */
        guard vm.notchState == .closed else { return }
        withAnimation(.smooth) { gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20 }
        if phase == .ended { withAnimation(.smooth) { gestureProgress = .zero } }
        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] { haptics.toggle() }
            withAnimation(.smooth) { gestureProgress = .zero }
            doOpen()
        }
    }
    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) { /* … igual … */
        if vm.notchState == .open && !vm.isHoveringCalendar {
            withAnimation(.smooth) { gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20 }
            if phase == .ended { withAnimation(.smooth) { gestureProgress = .zero } }
            if translation > Defaults[.gestureSensitivity] {
                withAnimation(.smooth) { gestureProgress = .zero; isHovering = false }
                vm.close()
                if Defaults[.enableHaptics] { haptics.toggle() }
            }
        }
    }
}

// MARK: - Modificadores auxiliares (sin tipos del VM)

private struct AnimationsModifier: ViewModifier {
    let useModernCloseAnimation: Bool
    @Binding var isHovering: Bool
    let isNotchOpen: Bool
    @Binding var gestureProgress: CGFloat

    func body(content: Content) -> some View {
        if !useModernCloseAnimation {
            let hoverAnim = Animation.bouncy.speed(1.2)
            let notchAnim = Animation.spring.speed(1.2)
            return AnyView(
                content
                    .animation(hoverAnim, value: isHovering)
                    .animation(notchAnim, value: isNotchOpen)
                    .animation(.smooth, value: gestureProgress)
                    .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
            )
        } else {
            let hoverAnim = Animation.bouncy.speed(1.2)
            let notchAnim = Animation.spring.speed(1.2)
            return AnyView(
                content
                    .animation(hoverAnim, value: isHovering)
                    .animation(notchAnim, value: isNotchOpen)
            )
        }
    }
}

private struct HoverGesturesModifier: ViewModifier {
    let openNotchOnHover: Bool
    let enableGestures: Bool
    let closeGestureEnabled: Bool
    let isNotchClosed: Bool

    @Binding var isHovering: Bool
    @Binding var haptics: Bool

    let handleHover: (Bool) -> Void
    let handleDownGesture: (CGFloat, NSEvent.Phase) -> Void
    let handleUpGesture: (CGFloat, NSEvent.Phase) -> Void
    let doOpen: () -> Void

    func body(content: Content) -> some View {
        var view = AnyView(content)

        if openNotchOnHover {
            view = AnyView(view.onHover { hovering in handleHover(hovering) })
        } else {
            view = AnyView(
                view
                    .onHover { hovering in
                        if isNotchClosed && Defaults[.enableHaptics] { haptics.toggle() }
                        withAnimation(.smooth) { isHovering = hovering }
                    }
                    .onTapGesture { doOpen() }
            )
            if enableGestures {
                view = AnyView(
                    view.panGesture(direction: .down) { t, p in handleDownGesture(t, p) }
                )
            }
        }

        if closeGestureEnabled && enableGestures {
            view = AnyView(
                view.panGesture(direction: .up) { t, p in handleUpGesture(t, p) }
            )
        }

        return view
    }
}

// Preview
#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
