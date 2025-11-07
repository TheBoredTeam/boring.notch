//
//  LoftNotchHomeView.swift
//  Zenith Loft (LoftOS)
//
//  Clean-room replacement for NotchHomeView.swift.
//  - No Defaults / BoringViewModel / BoringViewCoordinator / WebcamManager deps
//  - Parent passes state flags + injects Calendar and Camera views
//  - MusicManager.shared usage is preserved (replace with your own if needed)
//

import SwiftUI
import AppKit

// MARK: - Music Player Components (Loft versions)

public struct LoftMusicPlayerView: View {
    public let albumArtNamespace: Namespace.ID
    public let showShuffleAndRepeat: Bool

    public init(albumArtNamespace: Namespace.ID, showShuffleAndRepeat: Bool) {
        self.albumArtNamespace = albumArtNamespace
        self.showShuffleAndRepeat = showShuffleAndRepeat
    }

    public var body: some View {
        HStack {
            LoftAlbumArtView(albumArtNamespace: albumArtNamespace)
                .padding(5)
            LoftMusicControlsView(showShuffleAndRepeat: showShuffleAndRepeat)
                .drawingGroup()
                .compositingGroup()
        }
    }
}

public struct LoftAlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    public let albumArtNamespace: Namespace.ID

    // Replace these switches with your own settings screen later if you want.
    public var enableLightingEffect: Bool = true
    public var scaleCornersOnOpen: Bool = true
    public var showAppIconOverlay: Bool = true

    public init(albumArtNamespace: Namespace.ID,
                enableLightingEffect: Bool = true,
                scaleCornersOnOpen: Bool = true,
                showAppIconOverlay: Bool = true) {
        self.albumArtNamespace = albumArtNamespace
        self.enableLightingEffect = enableLightingEffect
        self.scaleCornersOnOpen = scaleCornersOnOpen
        self.showAppIconOverlay = showAppIconOverlay
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if enableLightingEffect { albumArtBackground }
            albumArtButton
        }
    }

    private var albumArtBackground: some View {
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
                    cornerRadius: scaleCornersOnOpen
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed
                )
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
                    if showAppIconOverlay && !musicManager.usingAppIconForArtwork {
                        AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 30, height: 30)
                            .offset(x: 10, y: 10)
                            .transition(.scale.combined(with: .opacity).animation(.bouncy.delay(0.3)))
                    }
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)

            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
    }

    private var albumArtImage: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8),
                               value: musicManager.isFlipping)
            )
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: scaleCornersOnOpen
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed
                )
            )
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
    }
}

public struct LoftMusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    public let showShuffleAndRepeat: Bool

    public init(showShuffleAndRepeat: Bool) {
        self.showShuffleAndRepeat = showShuffleAndRepeat
    }

    public var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            playbackControls
        }
        .buttonStyle(PlainButtonStyle())
        .frame(minWidth: 180)
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
            MarqueeText(
                $musicManager.songTitle,
                font: .headline,
                nsFont: .headline,
                textColor: .white,
                frameWidth: width
            )
            MarqueeText(
                $musicManager.artistName,
                font: .headline,
                nsFont: .headline,
                textColor: Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6),
                frameWidth: width
            )
            .fontWeight(.medium)
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            LoftMusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 8) {
            if showShuffleAndRepeat {
                HoverButton(icon: "shuffle",
                            iconColor: musicManager.isShuffled ? .red : .white,
                            scale: .medium) {
                    MusicManager.shared.toggleShuffle()
                }
            }
            HoverButton(icon: "backward.fill", scale: .medium) {
                MusicManager.shared.previousTrack()
            }
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                MusicManager.shared.togglePlay()
            }
            HoverButton(icon: "forward.fill", scale: .medium) {
                MusicManager.shared.nextTrack()
            }
            if showShuffleAndRepeat {
                HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                    MusicManager.shared.toggleRepeat()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off: return .white
        case .all, .one: return .red
        }
    }
}

// MARK: - Main Loft Notch Home

public struct LoftNotchHomeView<CalendarContent: View, CameraContent: View>: View {

    public let albumArtNamespace: Namespace.ID

    // Parent passes launch state and visibility choices
    public var isFirstLaunch: Bool = false
    public var showCalendar: Bool = true
    public var showCamera: Bool = false
    public var showShuffleAndRepeat: Bool = true

    // Inject content (so you can pass your own Calendar and Camera views)
    @ViewBuilder public var calendarContent: () -> CalendarContent
    @ViewBuilder public var cameraContent: () -> CameraContent

    public init(
        albumArtNamespace: Namespace.ID,
        isFirstLaunch: Bool = false,
        showCalendar: Bool = true,
        showCamera: Bool = false,
        showShuffleAndRepeat: Bool = true,
        @ViewBuilder calendarContent: @escaping () -> CalendarContent,
        @ViewBuilder cameraContent: @escaping () -> CameraContent
    ) {
        self.albumArtNamespace = albumArtNamespace
        self.isFirstLaunch = isFirstLaunch
        self.showCalendar = showCalendar
        self.showCamera = showCamera
        self.showShuffleAndRepeat = showShuffleAndRepeat
        self.calendarContent = calendarContent
        self.cameraContent = cameraContent
    }

    public var body: some View {
        Group {
            if !isFirstLaunch {
                mainContent
            }
        }
        .transition(.opacity.combined(with: .blurReplace))
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: (showCamera && showCalendar) ? 10 : 15) {
            LoftMusicPlayerView(albumArtNamespace: albumArtNamespace,
                                showShuffleAndRepeat: showShuffleAndRepeat)

            if showCalendar {
                calendarContent()
                    .frame(width: showCamera ? 170 : 215)
            }

            if showCamera {
                cameraContent()
            }
        }
        .transition(
            .opacity.animation(.smooth.speed(0.9))
                .combined(with: .blurReplace.animation(.smooth.speed(0.9)))
                .combined(with: .move(edge: .top))
        )
    }
}

// MARK: - Slider (Loft versions)

public struct LoftMusicSliderView: View {
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

    public init(sliderValue: Binding<Double>,
                duration: Binding<Double>,
                lastDragged: Binding<Date>,
                color: NSColor,
                dragging: Binding<Bool>,
                currentDate: Date,
                timestampDate: Date,
                elapsedTime: Double,
                playbackRate: Double,
                isPlaying: Bool,
                onValueChange: @escaping (Double) -> Void) {
        self._sliderValue = sliderValue
        self._duration = duration
        self._lastDragged = lastDragged
        self.color = color
        self._dragging = dragging
        self.currentDate = currentDate
        self.timestampDate = timestampDate
        self.elapsedTime = elapsedTime
        self.playbackRate = playbackRate
        self.isPlaying = isPlaying
        self.onValueChange = onValueChange
    }

    private var currentElapsedTime: Double {
        // Small buffer ensures meaningful delta
        guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else {
            return sliderValue
        }
        let delta = isPlaying ? currentDate.timeIntervalSince(timestampDate) : 0
        let elapsed = elapsedTime + (delta * playbackRate)
        return min(elapsed, duration)
    }

    public var body: some View {
        VStack {
            LoftCustomSlider(
                value: $sliderValue,
                range: 0...duration,
                color: Color(nsColor: color).ensureMinimumBrightness(factor: 0.8),
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 10, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundColor(Color(nsColor: color).ensureMinimumBrightness(factor: 0.6))
            .font(.caption)
        }
        .onChange(of: currentDate) {
            sliderValue = currentElapsedTime
        }
    }

    private func timeString(from seconds: Double) -> String {
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

public struct LoftCustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var thumbSize: CGFloat = 12

    public init(value: Binding<Double>,
                range: ClosedRange<Double>,
                color: Color = .white,
                dragging: Binding<Bool>,
                lastDragged: Binding<Date>,
                onValueChange: ((Double) -> Void)? = nil,
                thumbSize: CGFloat = 12) {
        self._value = value
        self.range = range
        self.color = color
        self._dragging = dragging
        self._lastDragged = lastDragged
        self.onValueChange = onValueChange
        self.thumbSize = thumbSize
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = max(0.0001, range.upperBound - range.lowerBound)

            let progress = (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                // Filled track
                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.bouncy.speed(1.4), value: dragging)
        }
    }
}

// MARK: - Color Brightness helper

private extension Color {
    func ensureMinimumBrightness(factor: CGFloat) -> Color {
        let f = max(0, min(1, factor))
        return self.opacity(1 - f).overlay(Color.white.opacity(f))
    }
}

// MARK: - Convenience initializer for empty calendar/camera

public extension LoftNotchHomeView where CalendarContent == EmptyView, CameraContent == EmptyView {
    init(
        albumArtNamespace: Namespace.ID,
        isFirstLaunch: Bool = false,
        showCalendar: Bool = false,
        showCamera: Bool = false,
        showShuffleAndRepeat: Bool = true
    ) {
        self.init(
            albumArtNamespace: albumArtNamespace,
            isFirstLaunch: isFirstLaunch,
            showCalendar: showCalendar,
            showCamera: showCamera,
            showShuffleAndRepeat: showShuffleAndRepeat,
            calendarContent: { EmptyView() },
            cameraContent: { EmptyView() }
        )
    }
}

// MARK: - Backwards-compat typealias (so old code compiles while you migrate)

public typealias NotchHomeView = LoftNotchHomeView<EmptyView, EmptyView>

// MARK: - Preview

#Preview {
    struct Demo: View {
        @Namespace var ns
        var body: some View {
            ZStack {
                Color.black
                LoftNotchHomeView(
                    albumArtNamespace: ns,
                    isFirstLaunch: false,
                    showCalendar: true,
                    showCamera: true,
                    showShuffleAndRepeat: true,
                    calendarContent: {
                        // Your CalendarView goes here
                        Text("Calendar")
                            .foregroundStyle(.white)
                            .frame(width: 215, height: 120)
                            .background(.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    },
                    cameraContent: {
                        // Your CameraPreviewView goes here
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.black.opacity(0.6))
                            .overlay(Image(systemName: "web.camera").foregroundStyle(.white))
                            .frame(width: 180, height: 120)
                    }
                )
                .padding(12)
            }
            .frame(width: 700, height: 180)
        }
    }
    return Demo()
}
