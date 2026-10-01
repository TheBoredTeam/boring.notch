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
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var notificationManager = SystemNotificationManager.shared
    @ObservedObject private var activityCenter = LiveActivityCenter.shared
    @ObservedObject private var extensionTabs = ExtensionTabRegistry.shared
    @ObservedObject private var shelfState = ShelfStateViewModel.shared
    @Default(.compactMode) private var compactMode
    @Default(.floatingTabsInStandardMode) private var floatingTabsInStandardMode
    @Default(.boringShelf) private var shelfEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activityWidth: CGFloat = 0
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero
    @State private var horizontalMediaGestureTriggered = false
    @State private var horizontalMediaGestureFeedback: CGFloat = .zero
    @State private var isHoveringMusicArea = false
    @State private var isHoveringTabs = false

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    // Use standardized animations from StandardAnimations enum
    private let animationSpring = StandardAnimations.interactive

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10
    private let nowPlayingFallbackNoticeWidth: CGFloat = 330
    /// Matches the popovers' dismiss delay; long enough to reach a control
    /// inside the panel without closing under the pointer.
    private let hoverExitDelayMilliseconds = 350

    init(extensionTabInput: ExtensionTabInputScope? = nil) {
        self.extensionTabInput = extensionTabInput
    }

    // MARK: - Corner Radius Scaling
    private var cornerRadiusScaleFactor: CGFloat? {
        guard Defaults[.cornerRadiusScaling] else { return nil }
        let effectiveHeight = displayClosedNotchHeight
        guard effectiveHeight > 0 else { return nil }
        return effectiveHeight / 38.0
    }

    /// Compact mode gets a rounder opened shape (35 vs 19) — at its smaller
    /// size the standard radius reads square rather than pill-like.
    private var openedInsets: (top: CGFloat, bottom: CGFloat) {
        compactMode ? compactCornerRadiusInsets.opened : cornerRadiusInsets.opened
    }

    private var topCornerRadius: CGFloat {
        // If the notch is open, return the opened radius.
        if vm.notchState == .open {
            return openedInsets.top
        }

        // For the closed notch, scale if enabled
        let baseClosedTop = cornerRadiusInsets.closed.top
        guard let scaleFactor = cornerRadiusScaleFactor else {
            return displayClosedNotchHeight > 0 ? baseClosedTop : 0
        }
        return max(0, baseClosedTop * scaleFactor)
    }

    private var currentNotchShape: NotchShape {
        // Scale bottom corner radius for closed notch shape when scaling is enabled.
        let baseClosedBottom = cornerRadiusInsets.closed.bottom
        let bottomCorner: CGFloat

        if vm.notchState == .open {
            bottomCorner = openedInsets.bottom
        } else if let scaleFactor = cornerRadiusScaleFactor {
            bottomCorner = max(0, baseClosedBottom * scaleFactor)
        } else {
            bottomCorner = displayClosedNotchHeight > 0 ? baseClosedBottom : 0
        }

        return NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCorner
        )
    }

    private var activityContext: LiveActivityContext {
        LiveActivityContext(
            displayID: vm.screenUUID ?? NSScreen.main?.displayUUID,
            isPresentationEnabled: !vm.hideOnClosed
        )
    }

    private var activitySnapshot: LiveActivitySnapshot {
        activityCenter.service.snapshot(in: activityContext)
    }

    private var selectedActivity: AnyNotchLiveActivity? {
        activitySnapshot.selectedID.flatMap { activityCenter.activity(for: $0) }
    }

    /// Native extension controls own pointer, scroll, and drop gestures inside
    /// their expanded content, in both standard and compact modes.
    private var isExtensionTabVisible: Bool {
        guard vm.notchState == .open, notificationManager.activeNotification == nil,
              case .extensionTab(let id) = coordinator.currentView else { return false }
        return extensionTabs.tab(for: id, presentation: tabPresentation) != nil
    }

    /// A notification is a glance, not a workspace — it doesn't need the full
    /// height the home/shelf tabs are sized for, and stretching to fill it
    /// just surrounds two lines of text with empty black.
    /// Every compact tab receives the same finite content region.
    private var openNotchHeight: CGFloat? {
        if notificationManager.activeNotification != nil { return 132 }
        return workspaceLayout.notchHeight
    }

    private var workspaceLayout: NotchWorkspaceLayout {
        NotchWorkspaceLayout(
            compactMode: compactMode,
            standardSize: vm.notchSize,
            horizontalInset: openedInsets.top + 12,
            topClearance: compactMode ? (vm.hasNotch ? displayClosedNotchHeight : 11) : max(38, displayClosedNotchHeight)
        )
    }

    private var tabPresentation: ExtensionTabPresentation { compactMode ? .compact : .regular }

    /// The standard header retains its controls and clearance even when the
    /// tab switcher moves below the notch, preserving native content bounds.
    private var showsHeader: Bool {
        vm.notchState == .open
            && notificationManager.activeNotification == nil
            && !compactMode
    }

    private var showsFloatingTabs: Bool {
        vm.notchState == .open && usesFloatingTabs
            && notificationManager.activeNotification == nil
            && NotchTabVisibility.shouldShow(
                compactMode: compactMode, shelfEnabled: shelfEnabled, shelfIsEmpty: shelfState.isEmpty,
                alwaysShowTabs: coordinator.alwaysShowTabs,
                hasExtensionTabs: !extensionTabs.tabs(for: tabPresentation).isEmpty
            )
    }

    private var usesFloatingTabs: Bool { compactMode || floatingTabsInStandardMode }

    private enum ClosedNotchContent: Equatable {
        case hello
        case nowPlayingFallback
        case activity(LiveActivityID)
        case osd(SneakContentType)
        case idle
    }

    private var closedNotchContent: ClosedNotchContent {
        if coordinator.helloAnimationRunning { return .hello }
        if nowPlayingFallbackNoticeActive { return .nowPlayingFallback }
        if let selected = activitySnapshot.selectedID { return .activity(selected) }
        if coordinator.shouldShowSneakPeek(on: vm.screenUUID) {
            return .osd(coordinator.sneakPeekState(for: vm.screenUUID).type)
        }
        return .idle
    }

    private var computedChinWidth: CGFloat {
        if shouldDisplayNowPlayingFallbackNotice { return nowPlayingFallbackNoticeWidth }
        if vm.notchState == .closed, selectedActivity != nil {
            return max(vm.closedNotchSize.width, activityWidth + 2 * cornerRadiusInsets.closed.bottom)
        }
        return vm.closedNotchSize.width
    }

    private var shouldDisplayNowPlayingFallbackNotice: Bool {
        vm.notchState == .closed && nowPlayingFallbackNoticeActive
    }

    private var nowPlayingFallbackNoticeActive: Bool {
        guard musicManager.nowPlayingNotice != nil else { return false }

        let selectedScreen = NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
        let targetScreenUUID = selectedScreen?.displayUUID ?? NSScreen.main?.displayUUID
        let currentScreen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let isConnected = vm.screenUUID == nil || currentScreen != nil
        let isTargetDisplay = vm.screenUUID == nil || vm.screenUUID == targetScreenUUID

        return isConnected
            && isTargetDisplay
            && !isNotchHeightZero
    }

    // If the closed notch height is 0 (any display/setting), display a 10pt nearly-invisible notch
    // instead of fully hiding it. This preserves layout while avoiding visual artifacts.
    private var isNotchHeightZero: Bool { vm.effectiveClosedNotchHeight == 0 }

    private var displayClosedNotchHeight: CGFloat { isNotchHeightZero ? 10 : vm.effectiveClosedNotchHeight }

    var body: some View {
        @Bindable var dropInteraction = vm.dropInteraction

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
                        vm.notchState == .open ? openedInsets.top : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                          .overlay(alignment: .top) {
                              displayClosedNotchHeight.isZero && vm.notchState == .closed ? nil
                        : Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: 6
                    )
                    // Removed conditional bottom padding when using custom 0 notch to keep layout stable
                    .opacity((isNotchHeightZero && vm.notchState == .closed) ? 0.01 : 1)

                mainLayout
                    // alignment: .top matters here — without it this frame
                    // defaults to centering, and shrinking the height for a
                    // notification (openNotchHeight < vm.notchSize.height)
                    // then pulls the visible top edge down by half the
                    // difference instead of staying flush with the window's
                    // top-anchored origin. That's what read as "the notch
                    // sits a bit off the top of the screen."
                    .frame(height: vm.notchState == .open ? openNotchHeight : nil, alignment: .top)
                    .conditionalModifier(true) { view in
                        return view
                            .animation(vm.notchState == .open ? StandardAnimations.open : StandardAnimations.close, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                            // Outermost on purpose: it only fires when the
                            // closed-state content changes (the key is stable
                            // across open/close), and when several keys change
                            // at once the innermost animation wins, so the
                            // open/close springs below keep precedence.
                            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: closedNotchContent)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if vm.notchState == .closed && !shouldDisplayNowPlayingFallbackNotice {
                            doOpen()
                        }
                    }
                    .conditionalModifier(Defaults[.enableGestures] && !shouldDisplayNowPlayingFallbackNotice) { view in
                        view
                            .panGesture(direction: .down, enabled: !isExtensionTabVisible && !isHoveringTabs) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures] && !shouldDisplayNowPlayingFallbackNotice) { view in
                        view
                            .panGesture(direction: .up, enabled: !isExtensionTabVisible && !isHoveringTabs) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.enableHorizontalMediaGestures] && Defaults[.enableGestures] && !shouldDisplayNowPlayingFallbackNotice) { view in
                        view
                            .panGesture(direction: .left, enabled: isHorizontalMediaGestureContext) { translation, phase in
                                handleNextTrackGesture(translation: translation, phase: phase)
                            }
                            .panGesture(direction: .right, enabled: isHorizontalMediaGestureContext) { translation, phase in
                                handlePreviousTrackGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        scheduleCloseIfNotHovering(overNotch: vm)
                    }
                    .onChange(of: vm.isPopoverActive) { _, _ in
                        scheduleCloseIfNotHovering(overNotch: vm)
                    }
                    .onReceive(extensionTabInput?.interactionChanges.eraseToAnyPublisher()
                               ?? Empty<Void, Never>().eraseToAnyPublisher()) { _ in
                        scheduleCloseIfNotHovering(overNotch: vm)
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
                        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: computedChinWidth)
                }
            }
            // One region includes both the notch and detached strip, plus
            // their transparent gap. Moving down to switch tabs never starts
            // a competing hover-exit timer.
            .contentShape(Rectangle())
            .onHover(perform: handleHover)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: coordinator.currentView)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: showsFloatingTabs)
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
        .background(alignment: .top) { dragDetector }
        .preferredColorScheme(.dark)
        .environmentObject(vm)
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
                if !isExtensionTabVisible && !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        @Bindable var dropInteraction = vm.dropInteraction

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
                    if shouldDisplayNowPlayingFallbackNotice,
                       let notice = musicManager.nowPlayingNotice {
                        nowPlayingFallbackNotice(notice)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    } else if vm.notchState == .closed, let activity = selectedActivity {
                        registeredActivity(activity)
                       } else if showsHeader {
                           // No tab bar over a notification: it's a glance,
                           // not a place to switch between home and shelf —
                           // and the header spans the full notch width,
                           // which is what was stretching the whole panel
                           // out around a short message.
                           BoringHeader(showsTabs: !usesFloatingTabs)
                               .frame(height: max(38, displayClosedNotchHeight))
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       }
                        // New case to enable compact notch on external displays
                        else if !vm.hasNotch {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: 11) // idle notch height is halved on non notch display
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: displayClosedNotchHeight)
                       }

                        if coordinator.shouldShowSneakPeek(on: vm.screenUUID) {
                           if (coordinator.sneakPeekState(for: vm.screenUUID).type != .music) && (coordinator.sneakPeekState(for: vm.screenUUID).type != .battery) && !Defaults[.inlineOSD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: coordinator.binding(for: vm.screenUUID).type,
                                  value: coordinator.binding(for: vm.screenUUID).value,
                                  icon: coordinator.binding(for: vm.screenUUID).icon,
                                  accent: coordinator.binding(for: vm.screenUUID).accent,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeekState(for: vm.screenUUID).type {
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
                           else if coordinator.sneakPeekState(for: vm.screenUUID).type == .music {
                               if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                   HStack(alignment: .center) {
                                       Image(systemName: "music.note")
                                       GeometryReader { geo in
                                           MarqueeText(musicManager.songTitle + " - " + musicManager.artistName, color: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, delayDuration: 1.0, frameWidth: geo.size.width)
                                       }
                                   }
                                   .foregroundStyle(.gray)
                                   .padding(.bottom, 10)
                               }
                           }
                       }
                        }
                      }
                      .conditionalModifier((coordinator.shouldShowSneakPeek(on: vm.screenUUID) && (coordinator.sneakPeekState(for: vm.screenUUID).type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.shouldShowSneakPeek(on: vm.screenUUID) && (coordinator.sneakPeekState(for: vm.screenUUID).type != .music) && (vm.notchState == .closed))) { view in
                          view
                              .fixedSize()
                      }
                      .zIndex(1)
            if vm.notchState == .open {
                VStack {
                    // An open notch with a live notification is showing the
                    // reply UI — the usual tabs can wait until it's dismissed.
                    if let notification = notificationManager.activeNotification {
                        NotificationExpandedView(notification: notification)
                            .id(notification.id)
                    } else {
                        switch coordinator.currentView {
                        case .home:
                            if compactMode {
                                CompactHomeView(
                                    albumArtNamespace: albumArtNamespace,
                                    horizontalMediaGestureFeedback: horizontalMediaGestureFeedback
                                )
                                .frame(width: workspaceLayout.contentWidth, height: workspaceLayout.contentHeight)
                                .onHover { isHoveringMusicArea = $0 }
                                .onDisappear { isHoveringMusicArea = false }
                            } else {
                                NotchHomeView(
                                    albumArtNamespace: albumArtNamespace,
                                    horizontalMediaGestureFeedback: horizontalMediaGestureFeedback,
                                    isHoveringMusicArea: $isHoveringMusicArea
                                )
                            }
                        case .shelf:
                            ShelfView(
                                dropInteraction: vm.dropInteraction,
                                animation: vm.animation,
                                compact: compactMode
                            )
                            .conditionalModifier(compactMode) { view in
                                view.frame(width: workspaceLayout.contentWidth, height: workspaceLayout.contentHeight)
                                    .clipped()
                            }
                        case .extensionTab(let id):
                            ExtensionTabContent(id: id, displayID: activityContext.displayID, presentation: tabPresentation)
                                .frame(
                                    width: workspaceLayout.contentWidth,
                                    height: workspaceLayout.contentHeight
                                )
                                .clipped()
                        }
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
        .onDrop(of: isExtensionTabVisible ? [] : [.fileURL, .url, .utf8PlainText, .plainText, .data],
                delegate: GeneralDropTargetDelegate(isTargeted: $dropInteraction.generalDropTargeting))
    }

    private func nowPlayingFallbackNotice(_ notice: NowPlayingFallbackNotice) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(notice.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .lineLimit(2)

            Spacer(minLength: 5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: nowPlayingFallbackNoticeWidth)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
        .onAppear {
            if musicManager.markNowPlayingNoticePresented(notice.id) {
                announceNowPlayingFallbackNotice(notice)
            }
        }
    }

    private func announceNowPlayingFallbackNotice(_ notice: NowPlayingFallbackNotice) {
        let announcement = "\(String(localized: notice.title)). \(String(localized: notice.subtitle))."
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func registeredActivity(_ activity: AnyNotchLiveActivity) -> some View {
        let maximumWidth = windowSize.width - 2 * cornerRadiusInsets.closed.bottom
        let viewContext = LiveActivityViewContext(
            displayID: activityContext.displayID,
            height: displayClosedNotchHeight,
            maximumSideWidth: max(0, (maximumWidth - vm.closedNotchSize.width - 2 * liveActivityEdgeMargin) / 2),
            isHovered: isHovering,
            gestureProgress: gestureProgress
        )
        return LiveActivityStack(
            canCycle: activitySnapshot.canCycle,
            onCycle: { direction in activityCenter.service.cycle(direction, in: activityContext) }
        ) {
            NotchActivityHost(
                contentID: activity.descriptor.id,
                safeAreaWidth: vm.closedNotchSize.width,
                height: viewContext.height,
                maximumWidth: maximumWidth,
                clearance: liveActivityEdgeMargin,
                onWidthChange: { width in
                    guard activitySnapshot.selectedID == activity.descriptor.id else { return }
                    activityWidth = width
                }
            ) {
                activity.leading(context: viewContext)
            } trailing: {
                activity.trailing(context: viewContext)
            }
            .environment(\.notchActivityAlbumArtNamespace, albumArtNamespace)
        }
    }

    @ViewBuilder
    var dragDetector: some View {
        @Bindable var dropInteraction = vm.dropInteraction

        if Defaults[.boringShelf] && vm.notchState == .closed && !shouldDisplayNowPlayingFallbackNotice {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: openNotchSize.height + shadowPadding)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $dropInteraction.dragDetectorTargeting) { providers in
            dropInteraction.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

}
// MARK: - Gesture & Hover Handling

extension ContentView {
    @discardableResult
    private func doOpen() -> Bool {
        var didOpen = false
        withAnimation(animationSpring) {
            didOpen = vm.open()
        }
        return didOpen
    }

    // MARK: - Hover Management

    /// Closes the open notch after the hover grace period unless a popover
    /// still owns the pointer.
    private func scheduleCloseIfNotHovering(overNotch notchViewModel: BoringViewModel) {
        guard notchViewModel.notchState == .open,
              !isHovering,
              !notchViewModel.isPopoverActive,
              extensionTabInput?.keepsNotchOpen != true else { return }
        hoverTask?.cancel()
        hoverTask = Task {
            try? await Task.sleep(for: .milliseconds(hoverExitDelayMilliseconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self.vm.notchState == .open,
                   !self.isHovering,
                   !self.vm.isPopoverActive,
                   self.extensionTabInput?.keepsNotchOpen != true,
                   !SharingStateManager.shared.preventNotchClose {
                    self.vm.close()
                }
            }
        }
    }

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()

        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }

            // Freeze the dismiss countdown the moment the pointer arrives,
            // not when the notch finishes opening. Opening waits out
            // minimumHoverDuration plus an animation, and a notification
            // near the end of its life would expire during that — so it
            // vanished exactly as the notch opened around it.
            if notificationManager.activeNotification != nil {
                notificationManager.holdActive()
            }

            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }

            guard vm.notchState == .closed,
                  !shouldDisplayNowPlayingFallbackNotice,
                  !coordinator.shouldShowSneakPeek(on: vm.screenUUID),
                  Defaults[.openNotchOnHover] else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.shouldDisplayNowPlayingFallbackNotice,
                          !self.coordinator.shouldShowSneakPeek(on: self.vm.screenUUID) else { return }

                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(hoverExitDelayMilliseconds))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }

                    // Pointer left — let the notification age out again.
                    self.notificationManager.resumeDismiss()

                    if self.vm.notchState == .open,
                       !self.vm.isPopoverActive,
                       self.extensionTabInput?.keepsNotchOpen != true,
                       !SharingStateManager.shared.preventNotchClose {
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
        guard isHorizontalMediaGestureContext else {
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
        guard !isHoveringTabs else { return false }
        switch vm.notchState {
        case .closed:
            return !vm.hideOnClosed
                && !activitySnapshot.canCycle
                && activitySnapshot.selectedID == BuiltinLiveActivityID.music

        case .open:
            return coordinator.currentView == .home && !musicManager.isPlayerIdle && isHoveringMusicArea
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
    let vm = BoringViewModel(camera: CameraModel())
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
