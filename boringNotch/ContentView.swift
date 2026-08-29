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
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var notificationManager = SystemNotificationManager.shared
    /// Which entry of the closed-notch activity stack is on top.
    @State private var activityIndex: Int = 0
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero
    @State private var horizontalMediaGestureTriggered = false
    @State private var horizontalMediaGestureFeedback: CGFloat = .zero
    @State private var isHoveringMusicArea = false

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.showNotHumanFace) var showNotHumanFace

    // Use standardized animations from StandardAnimations enum
    private let animationSpring = StandardAnimations.interactive

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10
    private let nowPlayingFallbackNoticeWidth: CGFloat = 330

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
        Defaults[.compactMode] ? compactCornerRadiusInsets.opened : cornerRadiusInsets.opened
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

    /// Closed-notch activities, newest first. A notification sits in front of
    /// music, so an incoming message takes over the display; when it expires
    /// it drops out of this list on its own and music comes back — no
    /// explicit "restore previous activity" bookkeeping needed.
    private var liveActivities: [LiveActivityItem] {
        var items: [LiveActivityItem] = []

        if let notification = notificationManager.activeNotification {
            items.append(.notification(notification))
        }

        let musicIsShowing = (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled
        if musicIsShowing {
            items.append(.music)
        }

        return items
    }

    /// A notification is a glance, not a workspace — it doesn't need the full
    /// height the home/shelf tabs are sized for, and stretching to fill it
    /// just surrounds two lines of text with empty black.
    /// nil means "size to content".
    ///
    /// Compact mode must use nil: this frame bounds hit-testing as well as
    /// layout, so any value shorter than the content leaves the transport
    /// row outside the hover region — moving toward the buttons registered
    /// as a hover-exit and closed the notch. The compact panel's height is
    /// controlled by its own internal padding instead, which is the honest
    /// lever anyway.
    private var openNotchHeight: CGFloat? {
        if notificationManager.activeNotification != nil { return 132 }
        return Defaults[.compactMode] ? nil : vm.notchSize.height
    }

    /// Compact mode drops the tab bar along with the tabs it switches
    /// between — there's only the player to show, so a switcher would have
    /// nothing to switch to. Also what keeps the panel narrow, since the
    /// header spans the full notch width.
    private var showsHeader: Bool {
        vm.notchState == .open
            && notificationManager.activeNotification == nil
            && !Defaults[.compactMode]
    }

    /// The activity currently on top of the stack — what the chin has to be
    /// sized for.
    private var selectedActivity: LiveActivityItem? {
        let items = liveActivities
        guard !items.isEmpty else { return nil }
        return items[min(max(activityIndex, 0), items.count - 1)]
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if shouldDisplayNowPlayingFallbackNotice {
            chinWidth = nowPlayingFallbackNoticeWidth
        } else if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = 640
        } else if vm.notchState == .closed, !vm.hideOnClosed, let activity = selectedActivity {
            // Sized for whichever activity is actually on top, not for
            // whichever happens to exist — otherwise swiping to music while a
            // notification is still in the stack leaves the chin at the
            // notification's width.
            switch activity {
            case .notification(let notification) where notification.detectedCode != nil:
                // The code + copy button live on the wing right of the
                // physical notch; a flat 420 assumes a narrow cutout, and on
                // standard-notch displays the wing fell short so the code
                // clipped under the hardware bezel.
                chinWidth = max(420, vm.closedNotchSize.width + 2 * 112)
            case .notification:
                chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
            case .music:
                chinWidth += (2 * max(0, displayClosedNotchHeight - 12) + 20 + 2 * liveActivityEdgeMargin + 2)
                // The inline song-change peek widens the pill itself, so the
                // chin has to grow with it — otherwise the hover region is
                // narrower than what's on screen.
                if showingInlineMusicPeek {
                    chinWidth += 2 * inlineMusicPeekLabelWidth
                }
            }
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, displayClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    private var shouldDisplayNowPlayingFallbackNotice: Bool {
        guard musicManager.nowPlayingNotice != nil else { return false }

        let selectedScreen = NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
        let targetScreenUUID = selectedScreen?.displayUUID ?? NSScreen.main?.displayUUID
        let currentScreen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let isConnected = vm.screenUUID == nil || currentScreen != nil
        let isTargetDisplay = vm.screenUUID == nil || vm.screenUUID == targetScreenUUID

        return isConnected
            && isTargetDisplay
            && vm.notchState == .closed
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
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        if vm.notchState == .closed && !shouldDisplayNowPlayingFallbackNotice {
                            doOpen()
                        }
                    }
                    .conditionalModifier(Defaults[.enableGestures] && !shouldDisplayNowPlayingFallbackNotice) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures] && !shouldDisplayNowPlayingFallbackNotice) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.enableHorizontalMediaGestures] && Defaults[.enableGestures] && !shouldDisplayNowPlayingFallbackNotice) { view in
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
                        // Keep the helper's banner keep-alive gate in sync
                        // with the effective open state (refcounted client-side).
                        if newState == .open {
                            XPCHelperClient.shared.notchOpened()
                        } else {
                            XPCHelperClient.shared.notchClosed()
                        }
                    }
                    .onDisappear {
                        // Balance the refcount: torn down while open (screen
                        // lock, display-set change, window teardown) means the
                        // open->closed onChange never fires — without this the
                        // helper's focus gate would stay stuck open forever.
                        if vm.notchState == .open {
                            XPCHelperClient.shared.notchClosed()
                        }
                    }
                    // A new notification always takes the front of the stack,
                    // even if the user had swiped away to music.
                    .onChange(of: notificationManager.activeNotification?.id) { _, newID in
                        if newID != nil { activityIndex = 0 }
                    }
                    // Activities disappear on their own (a notification
                    // expires, music stops). Keep the selection in range so
                    // the stack falls back to whatever is left instead of
                    // pointing past the end.
                    .onChange(of: liveActivities.count) { _, count in
                        if activityIndex >= count { activityIndex = max(count - 1, 0) }
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
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(
            width: max(windowSize.width, vm.notchSize.width),
            height: max(windowSize.height, vm.notchSize.height + shadowPadding),
            alignment: .top
        )
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

    @ViewBuilder
    func NotchLayout() -> some View {
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
                } else {
                    if shouldDisplayNowPlayingFallbackNotice,
                       let notice = musicManager.nowPlayingNotice {
                        nowPlayingFallbackNotice(notice)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    } else if coordinator.expandingView.type == .battery && coordinator.expandingView.show
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
                                    maxAdapterWatts: batteryModel.maxAdapterWatts,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: displayClosedNotchHeight, alignment: .center)
                        } else if coordinator.shouldShowSneakPeek(on: vm.screenUUID) && Defaults[.inlineOSD] && (coordinator.sneakPeekState(for: vm.screenUUID).type != .music) && (coordinator.sneakPeekState(for: vm.screenUUID).type != .battery) && vm.notchState == .closed {
                           InlineOSD(
                              type: coordinator.binding(for: vm.screenUUID).type,
                              value: coordinator.binding(for: vm.screenUUID).value,
                              icon: coordinator.binding(for: vm.screenUUID).icon,
                              accent: coordinator.binding(for: vm.screenUUID).accent,
                              hoverAnimation: $isHovering,
                              gestureProgress: $gestureProgress
                          )
                              .transition(.opacity)
                      } else if !liveActivities.isEmpty && vm.notchState == .closed && !vm.hideOnClosed {
                          LiveActivityStack(items: liveActivities, index: $activityIndex) { item in
                              switch item {
                              case .notification(let notification):
                                  NotificationLiveActivity(notification: notification)
                              case .music:
                                  MusicLiveActivity()
                                      .frame(alignment: .center)
                              }
                          }
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation()
                       } else if showsHeader {
                           // No tab bar over a notification: it's a glance,
                           // not a place to switch between home and shelf —
                           // and the header spans the full notch width,
                           // which is what was stretching the whole panel
                           // out around a short message.
                           BoringHeader()
                               .frame(height: max(24, displayClosedNotchHeight))
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
                                           MarqueeText(musicManager.songTitle + " - " + musicManager.artistName,  color: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, delayDuration: 1.0, frameWidth: geo.size.width)
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
                    } else if Defaults[.compactMode] {
                        // Player only — no tab switching, so currentView is
                        // ignored here rather than offering a shelf the
                        // compact layout has no room (or tab bar) for.
                        // 336 = Atoll's 420 base less 20%, which also lands
                        // within a few points of their Dynamic Island width
                        // (340) — the tighter of their two compact sizes.
                        CompactHomeView(albumArtNamespace: albumArtNamespace)
                            .frame(width: 336)
                    } else {
                        switch coordinator.currentView {
                        case .home:
                            NotchHomeView(
                                albumArtNamespace: albumArtNamespace,
                                horizontalMediaGestureFeedback: horizontalMediaGestureFeedback,
                                isHoveringMusicArea: $isHoveringMusicArea
                            )
                        case .shelf:
                            ShelfView(
                                dropInteraction: vm.dropInteraction,
                                animation: vm.animation
                            )
                        case .notes:
                            NotchNotesView()
                        }
                    }
                }
                .transition(
                    .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $dropInteraction.generalDropTargeting))
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
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 20)
            let faceScale = min(1.0, displayClosedNotchHeight / 30.0)
            AnimatedFace(height: 24.0 * faceScale, width: 30.0 * faceScale)
        }.frame(
            height: displayClosedNotchHeight,
            alignment: .center
        )
    }

    /// True while the song-change peek is expanding the closed pill inline.
    private var showingInlineMusicPeek: Bool {
        coordinator.expandingView.show
            && coordinator.expandingView.type == .music
            && Defaults[.sneakPeekStyles] == .inline
    }

    /// Width of the black centre section of the closed music pill.
    ///
    /// Derived from the real notch width rather than the previous hard-coded
    /// 380. That constant assumed a particular notch size: the title sits
    /// left of the cutout and the artist right of it, separated by a spacer
    /// as wide as the notch itself, so on a wider notch there was no room
    /// left for the artist and the labels collided. Sizing from
    /// closedNotchSize keeps a fixed label budget either side whatever the
    /// hardware is, and keeps liveActivityEdgeMargin in play so content
    /// clears the bezel — the inline path had dropped it entirely.
    private var musicActivityCenterWidth: CGFloat {
        let margin = vm.closedNotchSize.width - 4 + (2 * liveActivityEdgeMargin)
        guard showingInlineMusicPeek else { return margin }
        return margin + (2 * inlineMusicPeekLabelWidth)
    }

    /// Space reserved for the title (left of the cutout) and artist (right).
    private let inlineMusicPeekLabelWidth: CGFloat = 110

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack(spacing: 0) {
            // Closed-mode album art: scale padding and corner radius according to cornerRadiusScaleFactor
            let baseArtSize = displayClosedNotchHeight - 12
            let scaledArtSize: CGFloat = {
                if let scale = cornerRadiusScaleFactor {
                    return displayClosedNotchHeight - 12 * scale
                }
                return baseArtSize
            }()

            let closedCornerRadius: CGFloat = {
                let base = MusicPlayerImageSizes.cornerRadiusInset.closed
                if let scale = cornerRadiusScaleFactor {
                    return max(0, base * scale)
                }
                return base
            }()

            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: closedCornerRadius)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: scaledArtSize,
                    height: scaledArtSize
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    // .center, not .top: the album art beside this is
                    // vertically centered, so top-aligned labels sat visibly
                    // high against it.
                    HStack(alignment: .center) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                musicManager.songTitle,
                                color: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                delayDuration: 0.4,
                                frameWidth: inlineMusicPeekLabelWidth
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
                                .frame(width: inlineMusicPeekLabelWidth, alignment: .trailing)
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
                    .padding(.horizontal, 8)
                )
                .frame(width: musicActivityCenterWidth)

            HStack {
                MusicVisualizer(
                    isPlaying: musicManager.isPlaying,
                    tintColor: Defaults[.coloredSpectrogram]
                    ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.5)
                    : Color.gray
                )
                .frame(width: 18, height: 12)
            }
            .frame(
                width: max(
                    0,
                    displayClosedNotchHeight - 12
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    displayClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: displayClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        @Bindable var dropInteraction = vm.dropInteraction

        if Defaults[.boringShelf] && vm.notchState == .closed && !shouldDisplayNowPlayingFallbackNotice {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    @discardableResult
    private func doOpen() -> Bool {
        var didOpen = false
        withAnimation(animationSpring) {
            didOpen = vm.open()
        }
        return didOpen
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }

        if !hovering, shouldRetainHoverAtScreenTopEdge() {
            return
        }

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
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    if self.shouldRetainHoverAtScreenTopEdge() || self.vm.isMouseHovering() {
                        return
                    }

                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }

                    // Pointer left — let the notification age out again.
                    self.notificationManager.resumeDismiss()

                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    private func shouldRetainHoverAtScreenTopEdge(
        _ location: NSPoint = NSEvent.mouseLocation
    ) -> Bool {
        guard let screenFrame = getScreenFrame(vm.screenUUID),
              isHovering || vm.notchState == .open,
              location.y >= screenFrame.maxY - 1.5
        else {
            return false
        }

        return vm.isMouseHovering(position: location)
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
        guard vm.notchState == .open,
              !vm.isHoveringCalendar,
              !vm.isScrollGestureActive
        else {
            return
        }

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
