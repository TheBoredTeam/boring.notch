//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var extensionRegistry = NotchExtensionRegistry.shared
    @ObservedObject private var codexNotifications = CodexNotificationManager.shared

    private let musicManager = MusicManager.shared
    private let batteryModel = BatteryStatusViewModel.shared

    @State private var closedSnapshotRevision = 0
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var suppressHoverExpansion = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero
    @State private var horizontalMediaGestureTriggered = false
    @State private var horizontalMediaGestureFeedback: CGFloat = .zero
    @State private var isHoveringMusicArea = false
    @State private var isPresentingCodexPermission = false
    @State private var presentedCodexPermission: CodexJobNotification?
    @State private var permissionCollapseTask: Task<Void, Never>?

    @State private var haptics: Bool = false

    @Namespace private var albumArtNamespace

    @Default(.showNotHumanFace) private var showNotHumanFace

    // Use standardized animations from StandardAnimations enum
    private let animationSpring = StandardAnimations.interactive

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private func topCornerRadius(for snapshot: ClosedNotchRenderSnapshot?) -> CGFloat {
        snapshot?.topCornerRadius ?? cornerRadiusInsets.opened.top
    }

    private func currentNotchShape(for snapshot: ClosedNotchRenderSnapshot?) -> NotchShape {
        snapshot?.notchShape ?? NotchShape(
            topCornerRadius: cornerRadiusInsets.opened.top,
            bottomCornerRadius: cornerRadiusInsets.opened.bottom
        )
    }

    // If the closed notch height is 0 (any display/setting), display a 10pt nearly-invisible notch
    // instead of fully hiding it. This preserves layout while avoiding visual artifacts.
    private var isNotchHeightZero: Bool { vm.effectiveClosedNotchHeight == 0 }
    private var displayClosedNotchHeight: CGFloat {
        isNotchHeightZero ? 10 : vm.effectiveClosedNotchHeight
    }

    private var gestureScale: CGFloat {
        guard gestureProgress != 0 else { return 1 }
        return max(0.6, 1 + gestureProgress * 0.01)
    }

    private func makeClosedNotchSnapshot() -> ClosedNotchRenderSnapshot {
        _ = closedSnapshotRevision
        let displayHeight = displayClosedNotchHeight
        let sneakPeek = coordinator.sneakPeekState(for: vm.screenUUID)
        let renderData = ClosedNotchRenderData(
            music: .init(
                albumArt: musicManager.albumArt,
                title: musicManager.songTitle,
                artist: musicManager.artistName,
                tintColor: musicManager.avgColor,
                isPlaying: musicManager.isPlaying
            ),
            battery: .init(
                statusTextKey: batteryModel.statusTextKey,
                level: batteryModel.levelBattery,
                isCharging: batteryModel.isCharging,
                isInLowPowerMode: batteryModel.isInLowPowerMode,
                isPluggedIn: batteryModel.isPluggedIn,
                maxAdapterWatts: batteryModel.maxAdapterWatts
            ),
            osd: coordinator.binding(for: vm.screenUUID)
        )

        let extensionActivities = extensionRegistry.closedActivities(context: .init(
            surfaceID: vm.screenUUID ?? "primary",
            closedNotchWidth: vm.closedNotchSize.width,
            displayHeight: displayHeight
        ))
        let context = ClosedNotchSnapshotContext(
            closedNotchWidth: vm.closedNotchSize.width,
            displayHeight: displayHeight,
            idleHeight: vm.hasNotch ? displayHeight : 11,
            isHovering: isHovering,
            gestureProgress: gestureProgress,
            hideOnClosed: vm.hideOnClosed,
            showIdleFace: showNotHumanFace,
            musicLiveActivityEnabled: coordinator.musicLiveActivityEnabled,
            musicPlayerIdle: musicManager.isPlayerIdle,
            expandingViewVisible: coordinator.expandingView.show,
            expandingViewType: coordinator.expandingView.type,
            sneakPeek: sneakPeek,
            sneakPeekVisible: coordinator.shouldShowSneakPeek(on: vm.screenUUID),
            cornerRadiusScalingEnabled: Defaults[.cornerRadiusScaling],
            inlineOSDEnabled: Defaults[.inlineOSD],
            powerStatusNotificationsEnabled: Defaults[.showPowerStatusNotifications],
            sneakPeekStyle: Defaults[.sneakPeekStyles],
            renderData: renderData,
            extensionActivities: extensionActivities
        )

        return ClosedNotchRenderSnapshot(context: context)
    }

    var body: some View {
        @Bindable var dropInteraction = vm.dropInteraction

        let closedSnapshot: ClosedNotchRenderSnapshot? = vm.notchState == .closed
            ? makeClosedNotchSnapshot()
            : nil
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = notchLayout(closedSnapshot: closedSnapshot)
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        closedSnapshot?.presentation.metrics.horizontalChromeInset
                            ?? cornerRadiusInsets.opened.top
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape(for: closedSnapshot))
                    .overlay(alignment: .top) {
                        closedSnapshot?.displayHeight.isZero == true ? nil
                            : Rectangle()
                                .fill(.black)
                                .frame(height: 1)
                                .padding(.horizontal, topCornerRadius(for: closedSnapshot))
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: 6
                    )
                    .opacity((isNotchHeightZero && vm.notchState == .closed) ? 0.01 : 1)
                
                mainLayout
                    .frame(height: vm.notchState == .open ? vm.notchSize.height : nil)
                    .animation(
                        vm.notchState == .open
                            ? StandardAnimations.open
                            : StandardAnimations.close,
                        value: vm.notchState
                    )
                    .animation(.smooth, value: gestureProgress)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(
                            hovering,
                            extensionAllowsExpansion: closedSnapshot?.opensNotchOnHover
                        )
                    }
                    .onTapGesture {
                        guard vm.notchState == .closed else { return }
                        if closedSnapshot?.opensNotchOnTap ?? true {
                            doOpen()
                        }
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
                    .conditionalModifier(Defaults[.enableHorizontalMediaGestures] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .left) { translation, phase in
                                handleNextTrackGesture(translation: translation, phase: phase)
                            }
                            .panGesture(direction: .right) { translation, phase in
                                handlePreviousTrackGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            scheduleAutomaticClose()
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: codexNotifications.expandedPermissionNotificationID) { _, notificationID in
                        guard isPresentingCodexPermission, notificationID == nil else { return }
                        collapseCodexPermission()
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            scheduleAutomaticClose()
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(
                            width: closedSnapshot?.presentation.metrics.totalWidth
                                ?? vm.closedNotchSize.width,
                            height: vm.chinHeight
                        )
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .ignoresSafeArea(.all)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onReceive(musicManager.objectWillChange) { _ in
            invalidateClosedSnapshot()
        }
        .onReceive(batteryModel.objectWillChange) { _ in
            invalidateClosedSnapshot()
        }
        .onReceive(extensionRegistry.objectWillChange) { _ in
            invalidateClosedSnapshot()
        }
        .onChange(of: dropInteraction.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if Defaults[.boringShelf] && vm.notchState == .closed {
                    if doOpen() {
                        coordinator.currentView = .shelf
                    }
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if dropInteraction.dropEvent {
                    dropInteraction.dropEvent = false
                    return
                }

                dropInteraction.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    private func invalidateClosedSnapshot() {
        guard vm.notchState == .closed else { return }
        closedSnapshotRevision &+= 1
    }

    @ViewBuilder
    private func notchLayout(closedSnapshot: ClosedNotchRenderSnapshot?) -> some View {
        @Bindable var dropInteraction = vm.dropInteraction

        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else if let closedSnapshot {
                    ClosedNotchRenderer(
                        snapshot: closedSnapshot,
                        albumArtNamespace: albumArtNamespace,
                        onActivitySelect: handleClosedActivitySelection
                    )
                } else if !isPresentingCodexPermission {
                    BoringHeader()
                        .frame(height: max(24, displayClosedNotchHeight))
                        .opacity(
                            gestureProgress == 0
                                ? 1
                                : 1 - min(abs(gestureProgress) * 0.1, 0.3)
                        )
                }
            }
            .zIndex(1)

            if vm.notchState == .open {
                OpenNotchContentView(
                    albumArtNamespace: albumArtNamespace,
                    horizontalMediaGestureFeedback: horizontalMediaGestureFeedback,
                    isHoveringMusicArea: $isHoveringMusicArea,
                    gestureProgress: gestureProgress,
                    permissionNotification: presentedCodexPermission
                )
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $dropInteraction.generalDropTargeting))
    }

    @ViewBuilder
    private var dragDetector: some View {
        @Bindable var dropInteraction = vm.dropInteraction

        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(
                    of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
                    isTargeted: $dropInteraction.dragDetectorTargeting
                ) { providers in
                    dropInteraction.dropEvent = true
                    ShelfStateViewModel.shared.load(providers)
                    return true
                }
        } else {
            EmptyView()
        }
    }

    @discardableResult
    private func doOpen() -> Bool {
        var didOpen = false
        permissionCollapseTask?.cancel()
        permissionCollapseTask = nil
        withAnimation(animationSpring) {
            if let notification = codexNotifications.visibleNotification,
               notification.status == .needsAction(.permission) {
                codexNotifications.presentPermissionDetail(for: notification)
                presentedCodexPermission = notification
                isPresentingCodexPermission = true
            }
            didOpen = vm.open()
        }
        return didOpen
    }

    private func collapseCodexPermission() {
        guard isPresentingCodexPermission else { return }

        permissionCollapseTask?.cancel()
        withAnimation(StandardAnimations.close) {
            isPresentingCodexPermission = false
            vm.close()
        }

        let transitionDuration = CodexNotificationTiming.transitionDuration(
            animationSpeedMultiplier: Defaults[.animationSpeedMultiplier],
            animationsEnabled: Defaults[.enableOpeningAnimation]
        )
        permissionCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(transitionDuration))
            guard !Task.isCancelled else { return }
            presentedCodexPermission = nil
            codexNotifications.dismissPermissionDetail()
            permissionCollapseTask = nil
        }
    }

    // MARK: - Hover Management

    private func handleClosedActivitySelection() {
        hoverTask?.cancel()
        hoverTask = nil
        suppressHoverExpansion = true
        withAnimation(animationSpring) {
            isHovering = false
        }
    }

    private func handleHover(_ hovering: Bool, extensionAllowsExpansion: Bool?) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            let shouldExpand = extensionAllowsExpansion ?? Defaults[.openNotchOnHover]
            guard vm.notchState == .closed,
                  shouldExpand,
                  !suppressHoverExpansion,
                  !coordinator.shouldShowSneakPeek(on: vm.screenUUID) else { return }

            let hoverDuration = extensionAllowsExpansion == true
                ? max(
                    Defaults[.minimumHoverDuration],
                    CodexNotificationTiming.codexHoverExpansionDelay
                )
                : Defaults[.minimumHoverDuration]
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(hoverDuration))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.shouldShowSneakPeek(on: self.vm.screenUUID) else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            suppressHoverExpansion = false
            scheduleAutomaticClose(clearingHover: true)
        }
    }

    private var canAutomaticallyClose: Bool {
        vm.notchState == .open
            && !isHovering
            && !vm.isBatteryPopoverActive
            && codexNotifications.submittingNotificationIDs.isEmpty
            && !SharingStateManager.shared.preventNotchClose
    }

    private func scheduleAutomaticClose(clearingHover: Bool = false) {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }

            if clearingHover {
                withAnimation(animationSpring) {
                    isHovering = false
                }
            }

            if canAutomaticallyClose {
                if isPresentingCodexPermission {
                    collapseCodexPermission()
                } else {
                    vm.close()
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard !isPresentingCodexPermission, vm.notchState == .closed else { return }

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
        guard !isPresentingCodexPermission,
              vm.notchState == .open,
              !vm.isHoveringCalendar else { return }

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
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }

    private func handleNextTrackGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleHorizontalMediaGesture(translation: translation, phase: phase, feedback: -1) {
            musicManager.nextTrack()
        }
    }

    private func handlePreviousTrackGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleHorizontalMediaGesture(translation: translation, phase: phase, feedback: 1) {
            musicManager.previousTrack()
        }
    }

    private func handleHorizontalMediaGesture(
        translation: CGFloat,
        phase: NSEvent.Phase,
        feedback: CGFloat,
        action: () -> Void
    ) {
        guard !isPresentingCodexPermission, isHorizontalMediaGestureContext else {
            resetHorizontalMediaGesture()
            return
        }
        guard phase != .ended else {
            resetHorizontalMediaGesture()
            return
        }
        guard !horizontalMediaGestureTriggered else { return }
        guard translation > Defaults[.gestureSensitivity] else { return }

        horizontalMediaGestureTriggered = true
        triggerHorizontalMediaFeedback(feedback)
        action()

        if Defaults[.enableHaptics] {
            haptics.toggle()
        }
    }

    private func resetHorizontalMediaGesture() {
        horizontalMediaGestureTriggered = false
    }

    private func triggerHorizontalMediaFeedback(_ feedback: CGFloat) {
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.62)) {
            horizontalMediaGestureFeedback = feedback
            if vm.notchState == .closed {
                gestureProgress = 2
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(animationSpring) {
                horizontalMediaGestureFeedback = .zero
                if vm.notchState == .closed {
                    gestureProgress = .zero
                }
            }
        }
    }

    private var isHorizontalMediaGestureContext: Bool {
        switch vm.notchState {
        case .closed:
            guard !vm.hideOnClosed else { return false }

            if coordinator.shouldShowSneakPeek(on: vm.screenUUID) {
                return coordinator.sneakPeekState(for: vm.screenUUID).type == .music
            }

            guard !coordinator.expandingView.show || coordinator.expandingView.type == .music else {
                return false
            }

            return coordinator.musicLiveActivityEnabled && (musicManager.isPlaying || !musicManager.isPlayerIdle)

        case .open:
            return coordinator.currentView == .home && !musicManager.isPlayerIdle && isHoveringMusicArea
        }
    }
}

private struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .cancel)
    }

    func performDrop(info _: DropInfo) -> Bool {
        false
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
