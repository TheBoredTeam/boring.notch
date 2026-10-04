// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

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
    let extensionTabInput: ExtensionTabInputScope?
    @ObservedObject private var activityCenter = LiveActivityCenter.shared
    @ObservedObject private var extensionTabs = ExtensionTabRegistry.shared
    @ObservedObject private var shelfState = ShelfStateViewModel.shared
    @Default(.compactMode) private var compactMode
    @Default(.floatingTabsInStandardMode) private var floatingTabsInStandardMode
    @Default(.boringShelf) private var shelfEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activityWidth: CGFloat = 0
    @State private var isHoveringTabs = false

    init(extensionTabInput: ExtensionTabInputScope? = nil) {
        self.extensionTabInput = extensionTabInput
    }
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var openedInsets: (top: CGFloat, bottom: CGFloat) {
        compactMode ? compactCornerRadiusInsets.opened : cornerRadiusInsets.opened
    }

    private var activityContext: LiveActivityContext {
        LiveActivityContext(displayID: vm.screenUUID ?? NSScreen.main?.displayUUID,
                            isPresentationEnabled: !vm.hideOnClosed)
    }

    private var activitySnapshot: LiveActivitySnapshot {
        activityCenter.service.snapshot(in: activityContext)
    }

    private var selectedActivity: AnyNotchLiveActivity? {
        activitySnapshot.selectedID.flatMap { activityCenter.activity(for: $0) }
    }

    private var tabPresentation: ExtensionTabPresentation { compactMode ? .compact : .regular }
    private var usesFloatingTabs: Bool { compactMode || floatingTabsInStandardMode }
    private var isExtensionTabVisible: Bool {
        guard vm.notchState == .open, case .extensionTab(let id) = coordinator.currentView else { return false }
        return extensionTabs.tab(for: id, presentation: tabPresentation) != nil
    }

    private var workspaceLayout: NotchWorkspaceLayout {
        NotchWorkspaceLayout(compactMode: compactMode, standardSize: vm.notchSize,
                             horizontalInset: openedInsets.top + 12,
                             topClearance: max(24, vm.effectiveClosedNotchHeight))
    }

    private var showsFloatingTabs: Bool {
        vm.notchState == .open && usesFloatingTabs && NotchTabVisibility.shouldShow(
            compactMode: compactMode, shelfEnabled: shelfEnabled, shelfIsEmpty: shelfState.isEmpty,
            alwaysShowTabs: coordinator.alwaysShowTabs,
            hasExtensionTabs: !extensionTabs.tabs(for: tabPresentation).isEmpty
        )
    }

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? openedInsets.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? openedInsets.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var computedChinWidth: CGFloat {
        guard vm.notchState == .closed, selectedActivity != nil else { return vm.closedNotchSize.width }
        return max(vm.closedNotchSize.width, activityWidth + 2 * cornerRadiusInsets.closed.bottom)
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? Defaults[.cornerRadiusScaling]
                        ? (openedInsets.top) : (openedInsets.bottom)
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                mainLayout
                    .frame(height: vm.notchState == .open ? workspaceLayout.notchHeight : nil)
                    .conditionalModifier(true) { view in
                        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                        
                        return view
                            .animation(reduceMotion ? nil : (vm.notchState == .open ? openAnimation : closeAnimation), value: vm.notchState)
                            .animation(reduceMotion ? nil : .smooth, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if vm.notchState == .closed { doOpen() }
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down, enabled: !isExtensionTabVisible && !isHoveringTabs) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up, enabled: !isExtensionTabVisible && !isHoveringTabs) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        scheduleCloseIfNotHovering()
                    }
                    .onReceive(extensionTabInput?.interactionChanges.eraseToAnyPublisher()
                               ?? Empty<Void, Never>().eraseToAnyPublisher()) { _ in
                        scheduleCloseIfNotHovering()
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        scheduleCloseIfNotHovering()
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if showsFloatingTabs {
                    TabSelectionView(presentation: .floating(maximumWidth: NotchWorkspaceLayout.compactContentWidth))
                        .shadow(color: Defaults[.enableShadow] ? .black.opacity(0.45) : .clear, radius: 6, y: 2)
                        .onHover { isHoveringTabs = $0 }
                        .onDisappear { isHoveringTabs = false }
                        .padding(.top, NotchTabStripMetrics.floatingGap)
                        .transition(.opacity)
                }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
            // A single region includes the notch, detached strip, and their gap.
            .contentShape(Rectangle())
            .onHover(perform: handleHover)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: coordinator.currentView)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: showsFloatingTabs)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(reduceMotion ? nil : .smooth, value: gestureProgress)
        .background(alignment: .top) { dragDetector }
        .preferredColorScheme(.dark)
        .environmentObject(vm)
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
                if !isExtensionTabVisible && !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: vm.notchState == .closed ? .center : .leading) {
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
                } else {
                    if vm.notchState == .closed, let activity = selectedActivity {
                        registeredActivity(activity)
                    } else if vm.notchState == .open {
                        if compactMode {
                            Color.clear.frame(width: workspaceLayout.contentWidth,
                                              height: max(24, vm.effectiveClosedNotchHeight))
                        } else {
                            BoringHeader(showsTabs: !usesFloatingTabs)
                                .frame(height: max(24, vm.effectiveClosedNotchHeight))
                                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                        }
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
            if vm.notchState == .open {
                VStack {
                    switch coordinator.currentView {
                    case .home:
                        if compactMode {
                            CompactHomeView(albumArtNamespace: albumArtNamespace)
                                .frame(width: workspaceLayout.contentWidth, height: workspaceLayout.contentHeight)
                        } else {
                            NotchHomeView(albumArtNamespace: albumArtNamespace)
                        }
                    case .shelf:
                        ShelfView(compact: compactMode)
                            .conditionalModifier(compactMode) { view in
                                view.frame(width: workspaceLayout.contentWidth, height: workspaceLayout.contentHeight)
                                    .clipped()
                            }
                    case .extensionTab(let id):
                        ExtensionTabContent(id: id, displayID: activityContext.displayID, presentation: tabPresentation)
                            .frame(width: workspaceLayout.contentWidth, height: workspaceLayout.contentHeight)
                            .clipped()
                    }
                }
                .transition(
                    .scale(scale: reduceMotion ? 1 : 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: isExtensionTabVisible ? [] : [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    private func registeredActivity(_ activity: AnyNotchLiveActivity) -> some View {
        let maximumWidth = windowSize.width - 2 * cornerRadiusInsets.closed.bottom
        let context = LiveActivityViewContext(
            displayID: activityContext.displayID, height: vm.effectiveClosedNotchHeight,
            maximumSideWidth: max(0, (maximumWidth - vm.closedNotchSize.width - 2 * liveActivityEdgeMargin) / 2),
            isHovered: isHovering, gestureProgress: gestureProgress
        )
        return ActivityBrowser(canCycle: activitySnapshot.canCycle,
                               onCycle: { activityCenter.service.cycle($0, in: activityContext) }) {
            NotchActivityHost(contentID: activity.descriptor.id,
                              safeAreaWidth: vm.closedNotchSize.width, height: context.height,
                              maximumWidth: maximumWidth, clearance: liveActivityEdgeMargin,
                              onWidthChange: { width in
                guard activitySnapshot.selectedID == activity.descriptor.id else { return }
                activityWidth = width
            }) {
                activity.leading(context: context)
            } trailing: {
                activity.trailing(context: context)
            }
            .environment(\.notchActivityAlbumArtNamespace, albumArtNamespace)
        }
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: openNotchSize.height + shadowPadding)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
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

    private func scheduleCloseIfNotHovering() {
        guard vm.notchState == .open, !isHovering, !vm.isBatteryPopoverActive,
              extensionTabInput?.keepsNotchOpen != true else { return }
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, vm.notchState == .open, !isHovering,
                  !vm.isBatteryPopoverActive, extensionTabInput?.keepsNotchOpen != true,
                  !SharingStateManager.shared.preventNotchClose else { return }
            vm.close()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
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
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && self.extensionTabInput?.keepsNotchOpen != true && !SharingStateManager.shared.preventNotchClose {
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
        guard vm.notchState == .open && !vm.isHoveringCalendar && !isExtensionTabVisible else { return }

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
}


/// Selection is provider-independent; only deliberate horizontal drags cycle.
private struct ActivityBrowser<Content: View>: View {
    let canCycle: Bool
    let onCycle: (LiveActivityCycleDirection) -> Bool
    @ViewBuilder let content: () -> Content
    @Default(.enableGestures) private var enableGestures
    @State private var haptics = false

    var body: some View {
        content()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 14).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 24 else { return }
                cycle(value.translation.width < 0 ? .next : .previous)
            }, including: canCycle && enableGestures ? .all : .subviews)
            .accessibilityActions {
                if canCycle {
                    Button("Next activity") { cycle(.next) }
                    Button("Previous activity") { cycle(.previous) }
                }
            }
            .sensoryFeedback(.alignment, trigger: haptics)
    }

    private func cycle(_ direction: LiveActivityCycleDirection) {
        guard canCycle, onCycle(direction) else { return }
        if Defaults[.enableHaptics] { haptics.toggle() }
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

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
