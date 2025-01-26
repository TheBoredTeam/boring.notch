//
//  NotchHomeView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli
//

import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var musicManager: MusicManager
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HStack {
            AlbumArtView(musicManager: musicManager, vm: vm, albumArtNamespace: albumArtNamespace)
            MusicControlsView(musicManager: musicManager).drawingGroup().compositingGroup()
        }
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager: MusicManager
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
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            )
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Defaults[.cornerRadiusScaling] ? MusicPlayerImageSizes.cornerRadiusInset.opened : MusicPlayerImageSizes.cornerRadiusInset.closed))
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 35)
            .opacity(min(0.6, 1 - max(musicManager.albumArt.getBrightness(), 0.3)))
    }

    private var albumArtButton: some View {
        Button {
            musicManager.openMusicApp()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                albumArtImage
                appIconOverlay
            }
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(musicManager.isPlaying ? 1 : 0.4)
        .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
    }

    private var albumArtImage: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: musicManager.isFlipping)
            )
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Defaults[.cornerRadiusScaling] ? MusicPlayerImageSizes.cornerRadiusInset.opened : MusicPlayerImageSizes.cornerRadiusInset.closed))
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity).animation(.bouncy.delay(0.3)))
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager: MusicManager
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            playbackControls
        }
        .buttonStyle(PlainButtonStyle())
        .frame(minWidth: Defaults[.showMirror] && Defaults[.showCalendar] ? 140 : 180)
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
            MarqueeText($musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white, frameWidth: width)
            MarqueeText(
                $musicManager.artistName,
                font: .headline,
                nsFont: .headline,
                textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor)
                    .ensureMinimumBrightness(factor: 0.6) : .gray,
                frameWidth: width
            )
            .fontWeight(.medium)
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            MusicSliderView(
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
                musicManager.seekTrack(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 8) {
            HoverButton(icon: "backward.fill", scale: .medium) {
                musicManager.previousTrack()
            }
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                musicManager.togglePlayPause()
            }
            HoverButton(icon: "forward.fill", scale: .medium) {
                musicManager.nextTrack()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var batteryModel: BatteryStatusViewModel
    @EnvironmentObject var webcamManager: WebcamManager
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        .transition(.opacity.combined(with: .blurReplace))
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: 20) {
            MusicPlayerView(albumArtNamespace: albumArtNamespace)

            if Defaults[.showCalendar] {
                CalendarView()
                .onContinuousHover { phase in
                                if Defaults[.closeGestureEnabled] {
                                    switch phase {
                                        case .active:
                                            Defaults[.closeGestureEnabled] = false
                                        case .ended:
                                            Defaults[.closeGestureEnabled] = false
                                    }
                                }
                            }
                    .environmentObject(vm)
            }

            if Defaults[.showMirror] && webcamManager.cameraAvailable {
                CameraPreviewView(webcamManager: webcamManager)
                    .scaledToFit()
                    .opacity(vm.notchState == .closed ? 0 : 1)
                    .blur(radius: vm.notchState == .closed ? 20 : 0)
            }
        }
        .transition(.opacity.animation(.smooth.speed(0.9))
            .combined(with: .blurReplace.animation(.smooth.speed(0.9)))
            .combined(with: .move(edge: .top)))
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

    var currentElapsedTime: Double {
        guard !dragging && isPlaying, currentDate > lastDragged else { return sliderValue }
        let timeDifference = currentDate.timeIntervalSince(timestampDate)
        let elapsed = elapsedTime + (timeDifference * playbackRate)
        return min(elapsed, duration)
    }

    var body: some View {
        VStack {
            CustomSlider(
                value: $sliderValue,
                range: 0 ... duration,
                color: Defaults[.sliderColor] == SliderColorEnum.albumArt ? Color(
                    nsColor: color
                ).ensureMinimumBrightness(factor: 0.8) : Defaults[.sliderColor] == SliderColorEnum.accent ? Defaults[.accentColor] : .white,
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
            .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: color)
                .ensureMinimumBrightness(factor: 0.6) : .gray)
            .font(.caption)
        }
        .onChange(of: currentDate) { _ in
            sliderValue = currentElapsedTime
        }
    }

    func timeString(from seconds: Double) -> String {
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
    var thumbSize: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let filledTrackWidth = min(rangeSpan == .zero ? 0 : ((value - range.lowerBound) / rangeSpan) * width, width)

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

#Preview {
    NotchHomeView(albumArtNamespace: Namespace().wrappedValue)
        .environmentObject(MusicManager(vm: BoringViewModel())!)
        .environmentObject(BoringViewModel())
        .environmentObject(BatteryStatusViewModel(vm: BoringViewModel()))
        .environmentObject(WebcamManager())
}
