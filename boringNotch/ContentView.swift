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
    @ObservedObject var webcamManager = WebcamManager.shared

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
    @Default(.lyricsGradient) var lyricsGradient

    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.useModernCloseAnimation) var useModernCloseAnimation

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    // Lyrics state for active updates
    @State private var currentLyricDisplay: String = ""
    @State private var nextLyricDisplay: String = ""
    @State private var upcomingLyricDisplay: String = ""  // For stacked mode
    @State private var furtherLyricDisplay: String = ""   // For stacked mode
    @State private var currentLineIndex: Int = 0
    @State private var isLeftSideActive: Bool = true // For alternating mode

    // Helper to determine if current display has a notch
    private var hasNotch: Bool {
        let currentScreen = NSScreen.screens.first { $0.localizedName == vm.screen }
        return (currentScreen?.safeAreaInsets.top ?? 0) > 0
    }

    // Get lyrics display mode for current screen (per-display setting with fallback to global)
    private var currentDisplayLyricsMode: LyricsDisplayMode {
        guard let screenName = vm.screen else {
            return Defaults[.lyricsDisplayMode]
        }
        return Defaults[.perDisplayLyricsMode][screenName] ?? Defaults[.lyricsDisplayMode]
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Extended notch bar with lyrics (renders as one continuous element)
            if musicManager.isLyricsMode && vm.notchState == .closed && musicManager.isPlaying {
                // Single unified container with gradient background and content
                GeometryReader { geometry in
                    ZStack(alignment: .center) {
                        // Single continuous background: top fill + gradient bar
                        VStack(spacing: 0) {
                            // Top extension to screen edge
                            Rectangle()
                                .fill(.black)
                                .frame(height: 20)

                            // Main gradient bar (conditional based on settings)
                            if lyricsGradient {
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color(nsColor: musicManager.avgColor).opacity(0.3), location: 0.0),
                                        .init(color: Color.black, location: 0.25),
                                        .init(color: Color.black, location: 0.75),
                                        .init(color: Color(nsColor: musicManager.avgColor).opacity(0.3), location: 1.0)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(height: vm.effectiveClosedNotchHeight)
                            } else {
                                Rectangle()
                                    .fill(.black)
                                    .frame(height: vm.effectiveClosedNotchHeight)
                            }
                        }
                        .frame(height: vm.effectiveClosedNotchHeight + 20)

                        // Lyrics content overlaid on top
                        Group {
                            if currentDisplayLyricsMode == .stacked {
                                // Stacked mode: layout depends on whether display has notch
                                if !hasNotch {
                                    // No notch: single column vertical stack (full width)
                                    VStack(spacing: 4) {
                                        // Next line on top (dimmed)
                                        FloatingLyricsBubbleStackedSingle(isNext: true)
                                            .transition(.move(edge: .top).combined(with: .opacity))

                                        // Current line on bottom (highlighted)
                                        FloatingLyricsBubbleStackedSingle(isNext: false)
                                            .transition(.move(edge: .bottom).combined(with: .opacity))
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.horizontal, 16)
                                } else {
                                    // Has notch: 2x2 grid layout
                                    VStack(spacing: 3) {
                                        // Top row (current + next) - highlighted
                                        HStack(spacing: 0) {
                                            FloatingLyricsBubbleStackedGrid(line: currentLyricDisplay, isHighlighted: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                            Spacer()
                                                .frame(width: vm.closedNotchSize.width + (cornerRadiusInsets.closed.bottom * 2))

                                            FloatingLyricsBubbleStackedGrid(line: nextLyricDisplay, isHighlighted: true)
                                                .frame(maxWidth: .infinity, alignment: .trailing)
                                        }

                                        // Bottom row (upcoming + further) - dimmed
                                        HStack(spacing: 0) {
                                            FloatingLyricsBubbleStackedGrid(line: upcomingLyricDisplay, isHighlighted: false)
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                            Spacer()
                                                .frame(width: vm.closedNotchSize.width + (cornerRadiusInsets.closed.bottom * 2))

                                            FloatingLyricsBubbleStackedGrid(line: furtherLyricDisplay, isHighlighted: false)
                                                .frame(maxWidth: .infinity, alignment: .trailing)
                                        }
                                    }
                                    .frame(height: vm.effectiveClosedNotchHeight)
                                    .offset(y: 20 / 2)
                                }
                            } else {
                                // Flowing or Alternating mode: horizontal layout
                                HStack(spacing: 0) {
                                    // Left lyrics bubble
                                    FloatingLyricsBubble()
                                        .transition(.move(edge: .leading).combined(with: .opacity))
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    // Center notch spacing
                                    Spacer()
                                        .frame(width: vm.closedNotchSize.width + (cornerRadiusInsets.closed.bottom * 2))

                                    // Right lyrics bubble
                                    FloatingLyricsBubbleRight()
                                        .transition(.move(edge: .trailing).combined(with: .opacity))
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .frame(height: vm.effectiveClosedNotchHeight)
                                .offset(y: 20 / 2)  // Offset to align with gradient bar, not top fill
                            }
                        }
                    }
                }
                .frame(height: vm.effectiveClosedNotchHeight + 20)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: cornerRadiusInsets.closed.bottom,
                        bottomTrailingRadius: cornerRadiusInsets.closed.bottom,
                        topTrailingRadius: 0
                    )
                )
                .offset(y: -20)  // Pull up by top fill height to connect to screen edge
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                .onHover { hovering in
                    if Defaults[.openNotchOnHover] {
                        handleHover(hovering)
                    } else {
                        if (vm.notchState == .closed) && Defaults[.enableHaptics] {
                            haptics.toggle()
                        }

                        withAnimation(vm.animation) {
                            isHovering = hovering
                        }

                        if !hovering && vm.notchState == .open {
                            vm.close()
                        }
                    }
                }
            }

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
                        .drawingGroup()
                        : NotchShape(
                            topCornerRadius: cornerRadiusInsets.closed.top,
                            bottomCornerRadius: cornerRadiusInsets.closed.bottom
                        )
                        .drawingGroup()
                }
                .padding(
                    .bottom,
                    vm.notchState == .open && Defaults[.extendHoverArea]
                        ? 0
                        : (vm.effectiveClosedNotchHeight == 0)
                            ? zeroHeightHoverPadding
                            : 0
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
                            .blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
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
                            if (vm.notchState == .closed) && Defaults[.enableHaptics] {
                                haptics.toggle()
                            }

                            withAnimation(vm.animation) {
                                isHovering = hovering
                            }

                            // Only close if mouse leaves and the notch is open
                            if !hovering && vm.notchState == .open {
                                vm.close()
                            }
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
                .onChange(of: vm.isBatteryPopoverActive) { _, newPopoverState in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if !newPopoverState && !isHovering && vm.notchState == .open {
                            vm.close()
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
//                    #if DEBUG
//                    .disabled(false)
//                    #else
//                    .disabled(true)
//                    #endif
//                    .keyboardShortcut("E", modifiers: .command)
                }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: openNotchSize.width, maxHeight: openNotchSize.height, alignment: .top)
        .shadow(
            color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                ? .black.opacity(0.2) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
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
                    HelloAnimation().frame(width: 200, height: 80).onAppear(perform: {
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
                      } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          if !musicManager.isLyricsMode {
                              MusicLiveActivity()
                          }
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation().animation(.interactiveSpring, value: musicManager.isPlayerIdle)
                      } else if vm.notchState == .open {
                          BoringHeader()
                              .frame(height: max(24, vm.effectiveClosedNotchHeight))
                              .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
                              .animation(.spring(response: 1, dampingFraction: 1, blendDuration: 0.8), value: vm.notchState)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
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
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12))
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
    }

    // MARK: - Lyrics Grid Components

    @ViewBuilder
    func AmbientLyricsActivity() -> some View {
        let lyricsHeight: CGFloat = 38 // Height decreased by 2px
        
        // Left-aligned dynamic island with lyrics
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                // Music icon
                Image(systemName: "music.note")
                    .font(.caption)
                    .foregroundColor(.white)
                    .opacity(0.7)
                
                // Lyrics content
                VStack(spacing: 3) {
                    // Current line
                    Text(getCurrentDisplayLine() ?? "♪ ♫ ♪")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .frame(maxWidth: 250, alignment: .leading)
                    
                    // Next line (smaller)
                    Text(getNextDisplayLine() ?? "♪ ♫ ♪")
                        .font(.caption2)
                        .fontWeight(.regular)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                        .frame(maxWidth: 250, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: lyricsHeight / 2)
                    .fill(.black)
            )
            .frame(minWidth: 300, maxWidth: 400)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 20)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            // This will trigger UI updates for real-time lyrics
        }
    }
    
    private func getCurrentLyricsTime() -> Double {
        let timeDifference = musicManager.isPlaying ? Date().timeIntervalSince(musicManager.timestampDate) : 0
        return musicManager.elapsedTime + (timeDifference * musicManager.playbackRate)
    }
    
    private func getNextLyricLine() -> String {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return "♪ ♫ ♪" }
        let currentTime = getCurrentLyricsTime()
        
        // Get current line first
        let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime)
        
        // Find the next line after the current one
        if let currentIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine?.text && $0.startTime == currentLine?.startTime }) {
            let nextIndex = currentIndex + 1
            if nextIndex < lyrics.lines.count {
                return lyrics.lines[nextIndex].text
            }
        }
        
        // Fallback: find any line that starts after current time
        if let nextLine = lyrics.lines.first(where: { $0.startTime > currentTime }) {
            return nextLine.text
        }
        
        return "♪ ♫ ♪"
    }
    
    private func getUpcomingLyricLine() -> String {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return "♪ ♫ ♪" }
        let currentTime = getCurrentLyricsTime()
        
        // Get current line first
        let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime)
        
        // Find the line after next
        if let currentIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine?.text && $0.startTime == currentLine?.startTime }) {
            let upcomingIndex = currentIndex + 2
            if upcomingIndex < lyrics.lines.count {
                return lyrics.lines[upcomingIndex].text
            }
        }
        
        return "♪ ♫ ♪"
    }
    
    private func getFurtherLyricLine() -> String {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return "♪ ♫ ♪" }
        let currentTime = getCurrentLyricsTime()
        
        // Get current line first
        let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime)
        
        // Find the line after upcoming
        if let currentIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine?.text && $0.startTime == currentLine?.startTime }) {
            let furtherIndex = currentIndex + 3
            if furtherIndex < lyrics.lines.count {
                return lyrics.lines[furtherIndex].text
            }
        }
        
        return "♪ ♫ ♪"
    }
    
    // New display functions that handle early playback times better
    private func getCurrentDisplayLine() -> String? {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return nil }
        let currentTime = getCurrentLyricsTime()
        
        // If we have a current line at this time, use it
        if let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime) {
            return currentLine.text
        }
        
        // If no current line and we're early in the song, show the first line
        if currentTime < 10.0 && !lyrics.lines.isEmpty {
            return lyrics.lines[0].text
        }
        
        return nil
    }
    
    private func getNextDisplayLine() -> String? {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return nil }
        let currentTime = getCurrentLyricsTime()
        
        // If we have a current line, find the next one
        if let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime) {
            if let currentIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine.text && $0.startTime == currentLine.startTime }) {
                let nextIndex = currentIndex + 1
                if nextIndex < lyrics.lines.count {
                    return lyrics.lines[nextIndex].text
                }
            }
        }
        
        // If no current line and we're early in the song, show the second line
        if currentTime < 10.0 && lyrics.lines.count > 1 {
            return lyrics.lines[1].text
        }
        
        return nil
    }
    
    private func getUpcomingDisplayLine() -> String? {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return nil }
        let currentTime = getCurrentLyricsTime()
        
        // If we have a current line, find the line after next
        if let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime) {
            if let currentIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine.text && $0.startTime == currentLine.startTime }) {
                let upcomingIndex = currentIndex + 2
                if upcomingIndex < lyrics.lines.count {
                    return lyrics.lines[upcomingIndex].text
                }
            }
        }
        
        // If no current line and we're early in the song, show the third line
        if currentTime < 10.0 && lyrics.lines.count > 2 {
            return lyrics.lines[2].text
        }
        
        return nil
    }
    
    private func getFurtherDisplayLine() -> String? {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return nil }
        let currentTime = getCurrentLyricsTime()

        // If we have a current line, find the line after upcoming
        if let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime) {
            if let currentIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine.text && $0.startTime == currentLine.startTime }) {
                let furtherIndex = currentIndex + 3
                if furtherIndex < lyrics.lines.count {
                    return lyrics.lines[furtherIndex].text
                }
            }
        }

        // If no current line and we're early in the song, show the fourth line
        if currentTime < 10.0 && lyrics.lines.count > 3 {
            return lyrics.lines[3].text
        }

        return nil
    }

    // Update lyrics display for real-time updates
    private func updateLyricsDisplay() {
        guard let lyrics = musicManager.lyricsService.currentLyrics else {
            currentLyricDisplay = ""
            nextLyricDisplay = ""
            upcomingLyricDisplay = ""
            furtherLyricDisplay = ""
            currentLineIndex = 0
            return
        }

        let currentTime = getCurrentLyricsTime()

        // Find current line and its index
        if let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime),
           let foundIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine.text && $0.startTime == currentLine.startTime }) {

            // Check if we've moved to a new line
            let lineChanged = foundIndex != currentLineIndex

            if lineChanged {
                currentLineIndex = foundIndex

                // Toggle active side for alternating mode
                if currentDisplayLyricsMode == .alternating {
                    isLeftSideActive.toggle()
                }
            }

            // Update display text
            if currentLyricDisplay != currentLine.text {
                currentLyricDisplay = currentLine.text
            }

            // Update next line
            let nextIndex = foundIndex + 1
            if nextIndex < lyrics.lines.count {
                if nextLyricDisplay != lyrics.lines[nextIndex].text {
                    nextLyricDisplay = lyrics.lines[nextIndex].text
                }
            } else {
                nextLyricDisplay = ""
            }

            // Update upcoming line (for stacked mode)
            let upcomingIndex = foundIndex + 2
            if upcomingIndex < lyrics.lines.count {
                if upcomingLyricDisplay != lyrics.lines[upcomingIndex].text {
                    upcomingLyricDisplay = lyrics.lines[upcomingIndex].text
                }
            } else {
                upcomingLyricDisplay = ""
            }

            // Update further line (for stacked mode)
            let furtherIndex = foundIndex + 3
            if furtherIndex < lyrics.lines.count {
                if furtherLyricDisplay != lyrics.lines[furtherIndex].text {
                    furtherLyricDisplay = lyrics.lines[furtherIndex].text
                }
            } else {
                furtherLyricDisplay = ""
            }
        } else {
            currentLyricDisplay = ""
            nextLyricDisplay = ""
            upcomingLyricDisplay = ""
            furtherLyricDisplay = ""
        }
    }

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
                            cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                    )
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12))
            }
            .frame(
                width: max(
                    0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
                height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)))

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
                                (coordinator.expandingView.show && Defaults[.enableSneakPeek]
                                    && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor) : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.enableSneakPeek]
                                        && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music && Defaults[.enableSneakPeek]
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380 : vm.closedNotchSize.width + (isHovering ? 8 : 0))

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
                            width: max(
                                0,
                                vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)
                                    + gestureProgress / 2),
                            height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)),
                            alignment: .center)
                } else {
                    LottieAnimationView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: max(
                    0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
                height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)),
                alignment: .center)
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
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

                // Close the notch if it's open and battery popover is not active
                if vm.notchState == .open && !vm.isBatteryPopoverActive {
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

    // MARK: - Floating Lyrics Bubble

    @ViewBuilder
    func FloatingLyricsBubble() -> some View {
        let displayMode = currentDisplayLyricsMode
        let isFlowing = displayMode == .flowing
        let isAlternating = displayMode == .alternating

        HStack(alignment: .center, spacing: 8) {
            // Music icon
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .opacity(0.7)

            if isHovering {
                // Show song name when hovering
                Text(musicManager.songTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(0.9)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Show lyrics based on mode
                if isFlowing {
                    // Flowing mode: always show current line on left
                    Text(currentLyricDisplay.isEmpty ? "♪ ♫ ♪" : currentLyricDisplay)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .opacity(0.9)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isAlternating {
                    // Alternating mode: show current if left is active, next if not
                    if isLeftSideActive {
                        Text(currentLyricDisplay.isEmpty ? "♪ ♫ ♪" : currentLyricDisplay)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .opacity(0.95)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(nextLyricDisplay.isEmpty ? "♪ ♫ ♪" : nextLyricDisplay)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .opacity(0.5)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateLyricsDisplay()
        }
        .onAppear {
            updateLyricsDisplay()
        }
    }

    @ViewBuilder
    func FloatingLyricsBubbleRight() -> some View {
        let displayMode = currentDisplayLyricsMode
        let isFlowing = displayMode == .flowing
        let isAlternating = displayMode == .alternating

        HStack(alignment: .center, spacing: 8) {
            // Show lyrics based on mode
            if isFlowing {
                // Flowing mode: always show next line on right (dimmed)
                Text(nextLyricDisplay.isEmpty ? "♪ ♫ ♪" : nextLyricDisplay)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isAlternating {
                // Alternating mode: show current if right is active, next if not
                if !isLeftSideActive {
                    Text(currentLyricDisplay.isEmpty ? "♪ ♫ ♪" : currentLyricDisplay)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .opacity(0.95)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(nextLyricDisplay.isEmpty ? "♪ ♫ ♪" : nextLyricDisplay)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .opacity(0.5)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Music icon
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .opacity(0.7)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateLyricsDisplay()
        }
        .onAppear {
            updateLyricsDisplay()
        }
    }

    @ViewBuilder
    func FloatingLyricsBubbleStackedSingle(isNext: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // Music icon on left
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .opacity(0.7)

            // Lyrics text (centered)
            if isNext {
                // Next line (dimmed, on top)
                Text(nextLyricDisplay.isEmpty ? "♪ ♫ ♪" : nextLyricDisplay)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .opacity(0.6)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // Current line (highlighted, on bottom)
                Text(currentLyricDisplay.isEmpty ? "♪ ♫ ♪" : currentLyricDisplay)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(0.95)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Music icon on right
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .opacity(0.7)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateLyricsDisplay()
        }
        .onAppear {
            updateLyricsDisplay()
        }
    }

    @ViewBuilder
    func FloatingLyricsBubbleStackedGrid(line: String, isHighlighted: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            // Music icon
            Image(systemName: "music.note")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .opacity(isHighlighted ? 0.7 : 0.5)

            // Lyrics text
            Text(line.isEmpty ? "♪ ♫ ♪" : line)
                .font(.system(size: 11, weight: isHighlighted ? .semibold : .regular))
                .foregroundColor(.white)
                .opacity(isHighlighted ? 0.9 : 0.5)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateLyricsDisplay()
        }
        .onAppear {
            updateLyricsDisplay()
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
