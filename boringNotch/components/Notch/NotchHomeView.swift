//
//  NotchHomeView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool

    var body: some View {
        HStack {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace).frame(width: 120).padding(.all, 5 * (vm.notchSize.height / 190))
            MusicControlsView(horizontalMediaGestureFeedback: horizontalMediaGestureFeedback)
                .compositingGroup()
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringMusicArea = hovering
        }
        .onDisappear {
            isHoveringMusicArea = false
        }
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable().scaledToFit()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened)
            )
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)

            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
            .allowsHitTesting(false)
    }

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .interpolation(.high)
            .resizable().scaledToFit()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened)
            )
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            appIcon(for: musicManager.bundleIdentifier ?? MediaAppBundleID.appleMusic)
                .resizable().scaledToFit()
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @EnvironmentObject var vm: BoringViewModel
    let horizontalMediaGestureFeedback: CGFloat
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    @Default(.showRemainingTime) private var showRemainingTime

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            slotToolbar
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: geo.size.width)
                musicSlider
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MarqueeText(musicManager.songTitle, font: .headline, color: .white, frameWidth: width)
            MarqueeText(
                musicManager.artistName,
                font: .headline,
                color: Defaults[.playerColorTinting]
                    ? Color(nsColor: musicManager.avgColor)
                        .ensureMinimumBrightness(factor: 0.6) : .gray,
                frameWidth: width
            )
            .fontWeight(.medium)
            if Defaults[.enableLyrics] {
                TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                    let currentElapsed: Double = {
                        guard musicManager.isPlaying else { return musicManager.elapsedTime }
                        let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                        let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                        return min(max(progressed, 0), musicManager.songDuration)
                    }()
                    let lyricDisplay: (line: String, displayDuration: Double?, animationID: Double?) = {
                        if LyricsService.shared.isFetchingLyrics { return ("Loading lyrics…", nil, nil) }
                        if !LyricsService.shared.syncedLyrics.isEmpty {
                            let context = LyricsService.shared.lyricLineContext(at: currentElapsed)
                            let displayDuration = context.endTime.map { max($0 - currentElapsed, 0) }
                            return (context.text, displayDuration, context.startTime)
                        }
                        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                        let line = trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                        return (line, nil, nil)
                    }()
                    let line = lyricDisplay.line
                    let isPersian = line.unicodeScalars.contains { scalar in
                        let v = scalar.value
                        return v >= 0x0600 && v <= 0x06FF
                    }
                    let lyricFont: Font = isPersian
                        ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize)
                        : .subheadline
                    TimedLyricText(
                        line,
                        font: lyricFont,
                        nsFont: .subheadline,
                        color: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                        displayDuration: lyricDisplay.displayDuration,
                        animationID: lyricDisplay.animationID,
                        frameWidth: width
                    )
                    .lineLimit(1)
                    .opacity(musicManager.isPlaying ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var musicSlider: some View {
        MusicPlaybackTimeline(playbackRate: musicManager.playbackRate) { date in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                onValueChange: { newValue in
                    MusicManager.shared.seek(to: newValue)
                },
                trailingLabel: showRemainingTime ? .remaining : .duration
            )
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        let result = Array(padded.prefix(sanitizedLimit))
        // If calendar and camera are both visible alongside music, hide the edge slots
        let shouldHideEdges = Defaults[.showCalendar] && Defaults[.showMirror] && vm.camera.cameraAvailable && vm.camera.isSessionRunning
        if shouldHideEdges && result.count >= 5 {
            return Array(result.dropFirst().dropLast())
        }

        return result
    }

    private func slotView(for slot: MusicControlButton) -> some View {
        MusicControlSlotButton(
            slot: slot,
            horizontalMediaGestureFeedback: horizontalMediaGestureFeedback
        )
    }
}

/// A single transport button, shared by the standard and compact layouts so
/// both render the exact same controls — sizing, glyphs, swipe-to-skip
/// bounce — and can't drift apart.
struct MusicControlSlotButton: View {
    @ObservedObject var musicManager = MusicManager.shared
    let slot: MusicControlButton
    let horizontalMediaGestureFeedback: CGFloat

    var body: some View {
        Group {
            switch slot {
            case .shuffle:
                HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                    MusicManager.shared.toggleShuffle()
                }
            case .previous:
                HoverButton(icon: "backward.fill", scale: .medium) {
                    MusicManager.shared.previousTrack()
                }
                .scaleEffect(horizontalMediaGestureFeedback > 0 ? 1.12 : 1)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.62), value: horizontalMediaGestureFeedback)
            case .playPause:
                HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                    MusicManager.shared.togglePlay()
                }
            case .next:
                HoverButton(icon: "forward.fill", scale: .medium) {
                    MusicManager.shared.nextTrack()
                }
                .scaleEffect(horizontalMediaGestureFeedback < 0 ? 1.12 : 1)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.62), value: horizontalMediaGestureFeedback)
            case .repeatMode:
                HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                    MusicManager.shared.toggleRepeat()
                }
            case .mediaOutput:
                MediaOutputSlotButton()
            case .volume:
                VolumeControlView()
            case .favorite:
                FavoriteControlButton()
            case .goBackward:
                HoverButton(icon: "gobackward.15", scale: .medium) {
                    MusicManager.shared.skip(seconds: -15)
                }
            case .goForward:
                HoverButton(icon: "goforward.15", scale: .medium) {
                    MusicManager.shared.skip(seconds: 15)
                }
            case .none:
                Color.clear.frame(height: 1)
            }
        }
        .help(slot.actionLabel(isPlaying: musicManager.isPlaying, isFavorite: musicManager.isFavoriteTrack))
        .accessibilityLabel(slot.actionLabel(isPlaying: musicManager.isPlaying, isFavorite: musicManager.isFavoriteTrack))
        .accessibilityHidden(slot == .none)
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return .red
        }
    }
}

struct MusicPlaybackTimeline<Content: View>: View {
    let playbackRate: Double
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: playbackRate > 0 ? musicPlaybackTickInterval : nil)) { context in
            content(context.date)
        }
    }
}

private let musicPlaybackTickInterval: TimeInterval = 0.2

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

/// Audio-output slot for a control row. Shows where audio is going and
/// switches it, via a popover device picker. Both layouts use this through
/// MusicControlSlotButton.
struct MediaOutputSlotButton: View {
    @ObservedObject private var routeManager = AudioRouteManager.shared
    @State private var showingPicker = false

    var body: some View {
        HoverButton(icon: routeSymbol, scale: .medium) {
            // Enumerate on open rather than polling: devices come and go
            // (AirPods connecting, a display waking) and a list built at
            // launch would be stale by the time anyone opened it.
            routeManager.refreshDevices()
            showingPicker.toggle()
        }
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            AudioOutputPicker(routeManager: routeManager) {
                showingPicker = false
            }
        }
    }

    /// Prefer the live device's own icon; fall back to the resolver's
    /// classification before the first enumeration has run.
    private var routeSymbol: String {
        routeManager.activeDevice?.iconName ?? AudioOutputRouteResolver.shared.outputRouteSymbol()
    }
}

// Internal so the compact layout's slot row can share the padding rule.
extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)
            .help(MusicControlButton.volume.label)
            .accessibilityLabel(MusicControlButton.volume.label)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .accessibilityLabel(MusicControlButton.volume.label)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }

    /// Level-reactive speaker waves (v2.7.3 behavior). The route-device
    /// glyphs (AirPods, headphones, …) that replaced these belong to the
    /// media-output button beside this slot — duplicating them here made
    /// volume and output indistinguishable and static while dragging.
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool

    var body: some View {
        mainContent
            .transition(.opacity)
    }

    private var shouldShowCamera: Bool {
        Defaults[.showMirror] && vm.camera.cameraAvailable && vm.camera.isSessionRunning
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: (shouldShowCamera && Defaults[.showCalendar]) ? 10 : 15) {
            MusicPlayerView(
                albumArtNamespace: albumArtNamespace,
                horizontalMediaGestureFeedback: horizontalMediaGestureFeedback,
                isHoveringMusicArea: $isHoveringMusicArea
            )

            if Defaults[.showCalendar] {
                CalendarView()
                    .frame(width: shouldShowCamera ? 170 : 215)
                    .onHover { isHovering in
                        vm.isHoveringCalendar = isHovering
                    }
                    .environmentObject(vm)
                    .transition(.opacity)
            }

            if shouldShowCamera {
                CameraPreviewView(camera: vm.camera)
                    .scaledToFit()
                    .opacity(vm.notchState == .closed ? 0 : 1)
                    .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0), value: shouldShowCamera)
                
            }
        }
        .transition(.opacity)
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void

    // Ported from Atoll (GPL-3.0, itself a boring.notch fork) so the
    // trailing timestamp can count down instead of showing the duration.
    var trailingLabel: TrailingLabel = .duration

    enum TrailingLabel {
        case duration
        /// Counts down: "-2:56".
        case remaining
    }

    var body: some View {
        VStack {
            sliderCore
                .frame(height: sliderFrameHeight, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(trailingTimeText)
            }
            .fontWeight(.medium)
            .foregroundColor(timeLabelColor)
            .font(.caption)
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    private var sliderCore: some View {
        CustomSlider(
            value: $sliderValue,
            range: 0...duration,
            color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
            dragging: $dragging,
            lastDragged: $lastDragged,
            onValueChange: onValueChange
        )
    }

    private var timeLabelColor: Color {
        Defaults[.playerColorTinting]
            ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray
    }

    private var trailingTimeText: String {
        switch trailingLabel {
        case .duration:
            return timeString(from: duration)
        case .remaining:
            return "-" + timeString(from: max(duration - sliderValue, 0))
        }
    }

    private var sliderFrameHeight: CGFloat {
        10
    }

    func timeString(from seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}
