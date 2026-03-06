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

    var body: some View {
        HStack {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace).frame(width: 120).padding(.all, 5 * (vm.notchSize.height / 190))
            MusicControlsView().drawingGroup().compositingGroup()
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
            .resizable()
            .aspectRatio(contentMode: .fit)
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
                ZStack(alignment:.bottomTrailing) {
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
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened)
            )
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fit)
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
        @ObservedObject var webcamManager = WebcamManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit

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
                    let line: String = {
                        if LyricsService.shared.isFetchingLyrics { return "Loading lyrics…" }
                        if !LyricsService.shared.syncedLyrics.isEmpty {
                            return LyricsService.shared.lyricLine(at: currentElapsed)
                        }
                        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                    }()
                    let isPersian = line.unicodeScalars.contains { scalar in
                        let v = scalar.value
                        return v >= 0x0600 && v <= 0x06FF
                    }
                    MarqueeText(
                        line,
                        font: .subheadline,
                        color: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                        frameWidth: width
                    )
                    .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .subheadline)
                    .lineLimit(1)
                    .opacity(musicManager.isPlaying ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
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
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                slotView(for: slot)
                    .frame(alignment: .center)
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
        let shouldHideEdges = Defaults[.showCalendar] && Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
        if shouldHideEdges && result.count >= 5 {
            return Array(result.dropFirst().dropLast())
        }

        return result
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                MusicManager.shared.togglePlay()
            }
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                MusicManager.shared.toggleRepeat()
            }
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

private extension Array where Element == MusicControlButton {
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
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        // simplified: use a straightforward opacity transition
        .transition(.opacity)
    }

    private var shouldShowCamera: Bool {
        Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: (shouldShowCamera && Defaults[.showCalendar]) ? 10 : 15) {
            MusicPlayerView(albumArtNamespace: albumArtNamespace)

            if Defaults[.showCalendar] {
                CalendarView()
                    .onHover { isHovering in
                        vm.isHoveringCalendar = isHovering
                    }
                    .environmentObject(vm)
                .frame(width: shouldShowCamera ? 170 : 215)
                .transition(.opacity)
            }

            if shouldShowCamera {
                CameraPreviewView(webcamManager: webcamManager)
                    .scaledToFit()
                    .opacity(vm.notchState == .closed ? 0 : 1)
                    .blur(radius: vm.notchState == .closed ? 20 : 0)
                    .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0), value: shouldShowCamera)
            }
        }
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
}

struct WeatherTabView: View {
    private enum WeatherPage: String, CaseIterable, Identifiable {
        case current
        case forecast

        var id: String { self.rawValue }
    }

    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var weatherManager = WeatherManager.shared
    @Default(.showWeather) private var showWeather
    @Default(.weatherCity) private var weatherCity
    @Default(.weatherContentPreference) private var weatherContentPreference
    @State private var selectedPage: WeatherPage = .current

    private var openHeaderHeight: CGFloat {
        let closedDisplayHeight = vm.effectiveClosedNotchHeight == 0 ? 10 : vm.effectiveClosedNotchHeight
        return max(24, closedDisplayHeight)
    }

    private var contentHeight: CGFloat {
        // Keep Weather tab height aligned with ContentView.NotchLayout vertical math:
        // total open height - header - VStack spacing - open bottom inset.
        let notchLayoutSpacing: CGFloat = 8
        let openBottomInset: CGFloat = 12
        let availableHeight = vm.notchSize.height - openHeaderHeight - notchLayoutSpacing - openBottomInset
        return Swift.max(0, availableHeight)
    }

    private var showForecastPage: Bool {
        weatherContentPreference == .currentAndForecast
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !showWeather {
                statePanel {
                    Label(localized("weather_tab.off.title", fallback: "Weather is off"), systemImage: "cloud.slash")
                        .font(.subheadline.weight(.semibold))
                    Text(localized("weather_tab.off.message", fallback: "Turn on Show weather in Settings > Weather."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let snapshot = weatherManager.snapshot {
                weatherCanvas(for: snapshot, staleError: weatherManager.errorMessage)
            } else if weatherManager.isLoading || !weatherManager.hasLoadedAtLeastOnce {
                statePanel {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(localized("weather_tab.loading", fallback: "Loading weather..."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error = weatherManager.errorMessage {
                statePanel {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        localizedFormat(
                            "weather_tab.current_city_format",
                            fallback: "Current city: %@",
                            weatherCity
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        weatherManager.requestRefresh(replacingCurrent: true)
                    } label: {
                        Label(localized("weather_tab.retry", fallback: "Retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
            } else {
                statePanel {
                    Text(localized("weather_tab.unavailable", fallback: "Weather not available"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: contentHeight, maxHeight: contentHeight, alignment: .topLeading)
        .onAppear {
            if showWeather && weatherManager.snapshot == nil {
                weatherManager.requestRefresh()
            }
        }
        .onChange(of: showWeather) { _, newValue in
            guard newValue else { return }
            weatherManager.requestRefresh()
        }
        .onChange(of: weatherContentPreference) { _, newValue in
            if newValue == .currentOnly {
                selectedPage = .current
            }
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        let value = NSLocalizedString(key, comment: "")
        return value == key ? fallback : value
    }

    private func localizedFormat(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key, fallback: fallback), locale: Locale.current, arguments: arguments)
    }

    private func statePanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func weatherCanvas(for snapshot: WeatherSnapshot, staleError: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headerBar(for: snapshot, staleError: staleError)

            Group {
                if selectedPage == .current || !showForecastPage {
                    currentWeatherPage(for: snapshot)
                } else {
                    forecastWeatherPage(for: snapshot)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onEnded { value in
                        guard showForecastPage else { return }
                        if value.translation.width < -32 {
                            withAnimation(.smooth(duration: 0.22)) {
                                selectedPage = .forecast
                            }
                        } else if value.translation.width > 32 {
                            withAnimation(.smooth(duration: 0.22)) {
                                selectedPage = .current
                            }
                        }
                    }
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .clipped()
    }

    @ViewBuilder
    private func weatherPageButton(page: WeatherPage) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) {
                selectedPage = page
            }
        } label: {
            Text(
                page == .current
                    ? localized("weather_tab.segment.current", fallback: "Current")
                    : localized("weather_tab.segment.forecast", fallback: "Forecast")
            )
                .font(.caption.weight(.semibold))
                .foregroundStyle(selectedPage == page ? .white : .white.opacity(0.78))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selectedPage == page ? Color.white.opacity(0.16) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func currentWeatherPage(for snapshot: WeatherSnapshot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            heroBlock(for: snapshot, compact: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            metricsGrid(for: snapshot, limit: 4, compact: true, singleColumn: false)
                .frame(width: 236, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func forecastWeatherPage(for snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    localizedFormat(
                        "weather_tab.next_days_format",
                        fallback: "Next %d days",
                        6
                    )
                )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                dailyRow(for: snapshot, limit: 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func dailyRow(for snapshot: WeatherSnapshot, limit: Int) -> some View {
        let points = Array(snapshot.dailyForecast.prefix(max(1, limit)))
        if points.isEmpty {
            Text(localized("weather_tab.no_forecast", fallback: "No forecast data"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
        } else {
            HStack(spacing: 6) {
                ForEach(points) { day in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.dayLabel)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Image(systemName: WeatherCodeMapper.symbolName(for: day.weatherCode, isDay: true))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.92))
                            Text("\(Int(day.minTemperature.rounded()))° / \(Int(day.maxTemperature.rounded()))°")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }

                        if let rain = day.precipitationProbability {
                            Text(
                                localizedFormat(
                                    "weather_tab.rain_value_format",
                                    fallback: "Rain %d%%",
                                    Int(rain.rounded())
                                )
                            )
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private func headerBar(for snapshot: WeatherSnapshot, staleError: String?) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(snapshot.cityName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(
                localizedFormat(
                    "weather_tab.updated_format",
                    fallback: "Updated %@",
                    snapshot.updatedAt.formatted(date: .omitted, time: .shortened)
                )
            )
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)

            Spacer()

            if staleError != nil {
                Label(localized("weather_tab.cached_badge", fallback: "Cached"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.86))
            }

            if showForecastPage {
                HStack(spacing: 6) {
                    weatherPageButton(page: .current)
                    weatherPageButton(page: .forecast)
                }
            }

        }
    }

    @ViewBuilder
    private func heroBlock(for snapshot: WeatherSnapshot, compact: Bool) -> some View {
        let temperatureStyle = temperatureGradient(for: snapshot)
        let iconColors = weatherIconPalette(for: snapshot)

        HStack(alignment: .center, spacing: compact ? 12 : 14) {
            HStack(alignment: .center, spacing: compact ? 10 : 12) {
                Text(snapshot.temperatureText)
                    .font(.system(size: compact ? 46 : 52, weight: .bold, design: .rounded))
                    .foregroundStyle(temperatureStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)

                Image(systemName: snapshot.symbolName)
                    .font(.system(size: compact ? 34 : 40, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(iconColors.0, iconColors.1)
                    .shadow(color: iconColors.0.opacity(0.18), radius: 6, x: 0, y: 2)
            }
            .layoutPriority(2)

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.conditionText)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                if let highLow = highLowText(for: snapshot) {
                    Text(highLow)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func metricsGrid(for snapshot: WeatherSnapshot, limit: Int, compact: Bool, singleColumn: Bool) -> some View {
        let metrics: [(String, String, String)] = [
            (localized("weather_tab.metric.feels", fallback: "Feels"), snapshot.feelsLikeText ?? "--", "thermometer.medium"),
            (localized("weather_tab.metric.humidity", fallback: "Humidity"), snapshot.humidityText ?? "--", "humidity.fill"),
            (localized("weather_tab.metric.wind", fallback: "Wind"), snapshot.windSpeedText ?? "--", "wind"),
            (localized("weather_tab.metric.rain", fallback: "Rain"), snapshot.precipitationText ?? "--", "drop.fill")
        ]
        let visibleMetrics = Array(metrics.prefix(max(1, min(limit, metrics.count))))
        let columns = singleColumn ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]

        LazyVGrid(columns: columns, spacing: compact ? 4 : 6) {
            ForEach(visibleMetrics, id: \.0) { metric in
                HStack(spacing: 4) {
                    Image(systemName: metric.2)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.84))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(metric.0)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.78))
                        Text(metric.1)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, compact ? 3 : 5)
                .background(Color.black.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func hourlyRow(for snapshot: WeatherSnapshot, limit: Int, compact: Bool) -> some View {
        let points = Array(snapshot.hourlyForecast.prefix(max(1, limit)))

        if points.isEmpty {
            Text(localized("weather_tab.no_hourly", fallback: "No hourly forecast"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
        } else {
            HStack(spacing: compact ? 6 : 8) {
                ForEach(points) { point in
                    VStack(spacing: 2) {
                        Text(point.timeLabel)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.78))

                        Image(systemName: WeatherCodeMapper.symbolName(for: point.weatherCode, isDay: point.isDay))
                            .font(.caption)
                            .foregroundStyle(.white)

                        Text("\(Int(point.temperature.rounded()))°")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 3 : 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func highLowText(for snapshot: WeatherSnapshot) -> String? {
        guard let high = snapshot.highTemperature, let low = snapshot.lowTemperature else { return nil }
        return localizedFormat(
            "weather_tab.high_low_format",
            fallback: "L %d°  H %d°",
            Int(low.rounded()),
            Int(high.rounded())
        )
    }

    private func temperatureGradient(for snapshot: WeatherSnapshot) -> LinearGradient {
        let celsius = snapshot.unit == .fahrenheit
            ? (snapshot.temperature - 32.0) * 5.0 / 9.0
            : snapshot.temperature

        switch celsius {
        case 32...:
            return LinearGradient(
                colors: [Color(red: 1.00, green: 0.52, blue: 0.44), Color(red: 0.95, green: 0.28, blue: 0.30)],
                startPoint: .top,
                endPoint: .bottom
            )
        case 26..<32:
            return LinearGradient(
                colors: [Color(red: 1.00, green: 0.72, blue: 0.36), Color(red: 1.00, green: 0.52, blue: 0.30)],
                startPoint: .top,
                endPoint: .bottom
            )
        case 18..<26:
            return LinearGradient(
                colors: [Color(red: 0.43, green: 0.86, blue: 0.66), Color(red: 0.33, green: 0.73, blue: 0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
        case 10..<18:
            return LinearGradient(
                colors: [Color(red: 0.60, green: 0.82, blue: 1.00), Color(red: 0.41, green: 0.66, blue: 0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            return LinearGradient(
                colors: [Color.white.opacity(0.98), Color(red: 0.86, green: 0.91, blue: 0.98)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func weatherIconPalette(for snapshot: WeatherSnapshot) -> (Color, Color) {
        switch snapshot.weatherCode {
        case 0:
            return snapshot.isDay
                ? (Color(red: 1.00, green: 0.84, blue: 0.34), Color(red: 1.00, green: 0.62, blue: 0.28))
                : (Color(red: 0.76, green: 0.82, blue: 1.00), Color(red: 0.58, green: 0.64, blue: 0.92))
        case 1, 2:
            return snapshot.isDay
                ? (Color(red: 1.00, green: 0.80, blue: 0.36), Color.white.opacity(0.95))
                : (Color(red: 0.66, green: 0.76, blue: 1.00), Color.white.opacity(0.88))
        case 3, 45, 48:
            return (Color.white.opacity(0.94), Color(red: 0.68, green: 0.72, blue: 0.79))
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82:
            return (Color(red: 0.45, green: 0.84, blue: 1.00), Color(red: 0.28, green: 0.60, blue: 0.96))
        case 71, 73, 75, 77, 85, 86:
            return (Color.white.opacity(0.99), Color(red: 0.74, green: 0.90, blue: 1.00))
        case 95, 96, 99:
            return (Color(red: 1.00, green: 0.86, blue: 0.36), Color(red: 0.62, green: 0.60, blue: 1.00))
        default:
            return (Color.white.opacity(0.95), Color.white.opacity(0.76))
        }
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


    var body: some View {
        VStack {
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
            .frame(height: 10, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundColor(
                Defaults[.playerColorTinting]
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray
            )
            .font(.caption)
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
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
