//
//  NotchHomeView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-18.
//

import SwiftUI
import Defaults
import Combine

struct NotchHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var batteryModel: BatteryStatusViewModel
    @EnvironmentObject var webcamManager: WebcamManager
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var timer: AnyCancellable?
    @State private var lastDragged: Date = .distantPast
    let albumArtNamespace: Namespace.ID
    
    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                HStack(alignment: .top, spacing: 30) {
                    HStack {
                        ZStack(alignment: .bottomTrailing) {
                            if Defaults[.lightingEffect] {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .background(
                                        Image(nsImage: musicManager.albumArt)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    )
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: Defaults[.cornerRadiusScaling] ? MusicPlayerImageSizes.cornerRadiusInset.opened : MusicPlayerImageSizes.cornerRadiusInset.closed))
                                    .scaleEffect(x: 1.4, y: 1.4)
                                    .rotationEffect(.degrees(92))
                                    .blur(radius: 35)
                                    .opacity(min(0.6, 1 - max(musicManager.albumArt.getBrightness(), 0.3)))
                                    .onAppear {
                                        print(musicManager.albumArt.getBrightness())
                                    }
                            }
                            
                            
                            Button {
                                musicManager.openMusicApp()
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit)
                                        .background(
                                            Image(nsImage: musicManager.albumArt)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        )
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: Defaults[.cornerRadiusScaling] ? MusicPlayerImageSizes.cornerRadiusInset.opened : MusicPlayerImageSizes.cornerRadiusInset.closed))
                                        .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                                    
                                    if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
                                        AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 30, height: 30)
                                            .offset(x: 10, y: 10)
                                            .transition(.scale.combined(with: .opacity).animation(.bouncy.delay(0.3)))
                                    }
                                }
                                .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .opacity(musicManager.isPlaying ? 1 : 0.4)
                            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
                        }
                        
                        VStack(alignment: .leading) {
                            GeometryReader { geo in
                                VStack(alignment: .leading, spacing: 4){
                                    VStack(alignment: .leading, spacing: 0) {
                                        MarqueeText($musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white, frameWidth: geo.size.width)
                                        MarqueeText(
                                            $musicManager.artistName,
                                            font: .headline,
                                            nsFont: .headline,
                                            textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor)
                                                .ensureMinimumBrightness(factor: 0.6) : .gray,
                                            frameWidth: geo.size.width
                                        )
                                        .fontWeight(.medium)
                                    }
                                    
                                    MusicSliderView(sliderValue: $sliderValue,
                                                    duration: $musicManager.songDuration,
                                                    lastDragged: $lastDragged,
                                                    color: musicManager.avgColor,
                                                    dragging: $dragging) { newValue in
                                        musicManager.seekTrack(to: newValue)
                                    }
                                                    .padding(.top, 5)
                                                    .frame(height: 36)
                                }
                            }
                            .padding(.top, 10)
                            .padding(.leading, 5)
                            
                            HStack(spacing: 8) {
                                HoverButton(icon: "backward.fill", scale: .medium) {
                                    musicManager.previousTrack()
                                }
                                HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                                    print("tapped")
                                    musicManager.togglePlayPause()
                                }
                                HoverButton(icon: "forward.fill", scale: .medium) {
                                    musicManager.nextTrack()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .frame(minWidth: 170)
                    }
                    
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
                    }
                    
                    if Defaults[.showMirror] && webcamManager.cameraAvailable && webcamManager.authorizationStatus != .denied {
                        CameraPreviewView(webcamManager: webcamManager)
                            .scaledToFit()
                            .opacity(vm.notchState == .closed ? 0 : 1)
                            .blur(radius: vm.notchState == .closed ? 20 : 0)
                    }
                    
                    if (!Defaults[.showMirror] || !webcamManager.cameraAvailable || webcamManager.authorizationStatus == .denied) && !Defaults[.showCalendar] {
                        Rectangle()
                            .fill(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor).gradient : Color.gray.gradient)
                            .mask {
                                AudioSpectrumView(
                                    isPlaying: $musicManager.isPlaying
                                )
                                .frame(width: 16, height: 12)
                            }
                            .frame(width: 50, alignment: .center)
                            .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                    }
                    //                BoringSystemTiles()
                    //                    .transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3)).delay(0.1)))
                    //                    .opacity(vm.notchState == .closed ? 0 : 1)
                    //                    .blur(radius: vm.notchState == .closed ? 20 : 0)
                }
                .onAppear {
                    // Initialize the slider value and start the timer
                    sliderValue = musicManager.elapsedTime
                    startTimer()
                }
                .onDisappear {
                    // Stop the timer when the view disappears
                    timer?.cancel()
                }
                .transition(.opacity.animation(.smooth.speed(0.9)).combined(with: .blurReplace.animation(.smooth.speed(0.9))).combined(with: .move(edge: .top)))
                .blur(radius: vm.notchState == .closed ? 30 : 0)
            }
            .transition(.opacity.combined(with: .blurReplace))
        }
        .transition(.opacity.combined(with: .blurReplace))
    }
    
    private func startTimer() {
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [self] _ in
                self.updateSliderValue()
            }
    }
    
    private func updateSliderValue() {
        guard !dragging, musicManager.timestampDate > lastDragged else { return }
        let currentTime = Date()
        let timeDifference = (musicManager.isPlaying ? currentTime.timeIntervalSince(musicManager.timestampDate) : musicManager.lastUpdated.timeIntervalSince(musicManager.timestampDate))
        // Calculate the real-time elapsed time
        let currentElapsedTime = musicManager.elapsedTime + (timeDifference * musicManager.playbackRate)
        sliderValue = min(currentElapsedTime, musicManager.songDuration)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    var onValueChange: ((Double) -> Void)
    
    var body: some View {
        VStack {
            CustomSlider(
                value: $sliderValue,
                range: 0...duration,
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
