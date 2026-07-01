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

private let homeWidgetCardHeight: CGFloat = 214

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HStack {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace).padding(.all, 5)
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
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
            .aspectRatio(1, contentMode: .fit)
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
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
    }
                

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
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
            MarqueeText(
                $musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white,
                frameWidth: width)
            MarqueeText(
                $musicManager.artistName,
                font: .headline,
                nsFont: .headline,
                textColor: Defaults[.playerColorTinting]
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
                        if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                        if !musicManager.syncedLyrics.isEmpty {
                            return musicManager.lyricLine(at: currentElapsed)
                        }
                        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                    }()
                    let isPersian = line.unicodeScalars.contains { scalar in
                        let v = scalar.value
                        return v >= 0x0600 && v <= 0x06FF
                    }
                    MarqueeText(
                        .constant(line),
                        font: .subheadline,
                        nsFont: .subheadline,
                        textColor: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
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
        return Array(padded.prefix(sanitizedLimit))
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

    @Default(.pomodoroEnabled) private var pomodoroEnabled
    @Default(.quickLaunchApps) private var quickLaunchApps
    @Default(.quickLaunchEnabled) private var quickLaunchEnabled
    @Default(.weatherFeatureEnabled) private var weatherFeatureEnabled
    @Default(.homeWidgetSlots) private var homeWidgetSlots

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
        VStack(alignment: .leading, spacing: 14) {
            if shouldShowUtilityRow {
                utilityRow
            }

            if shouldShowCamera {
                footerRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }

    private var shouldShowUtilityRow: Bool {
        homeSlots.contains { $0 != .hidden }
    }

    private var homeSlots: [HomeWidgetKind] {
        normalizedHomeWidgetSlots(homeWidgetSlots)
    }

    private var utilityRow: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(homeSlots.enumerated()), id: \.offset) { index, widget in
                homeWidget(for: widget, slotNumber: index + 1)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func homeWidget(for widget: HomeWidgetKind, slotNumber: Int) -> some View {
        switch widget {
        case .weather:
            if weatherFeatureEnabled {
                HomeWeatherCard()
            } else {
                HomeDisabledWidgetCard(title: "天气", subtitle: "Weather", message: "在 Weather 设置中开启。")
            }
        case .pomodoro:
            if pomodoroEnabled {
                HomePomodoroCard()
            } else {
                HomeDisabledWidgetCard(title: "Pomodoro", subtitle: "Focus", message: "在 Pomodoro 设置中开启。")
            }
        case .quickLaunch:
            if quickLaunchEnabled {
                QuickLaunchHomeCard(apps: quickLaunchApps)
            } else {
                HomeDisabledWidgetCard(title: "Quick launch", subtitle: "Apps", message: "在 Appearance 设置中开启。")
            }
        case .calendar:
            if Defaults[.showCalendar] {
                HomeCalendarPanel()
                    .environmentObject(vm)
            } else {
                HomeDisabledWidgetCard(title: "日历", subtitle: "Calendar", message: "在 Calendar 设置中开启。")
            }
        case .media:
            HomeMediaCard()
        case .hidden:
            Color.clear
                .frame(maxWidth: .infinity, minHeight: homeWidgetCardHeight, maxHeight: homeWidgetCardHeight)
                .accessibilityHidden(true)
        }
    }

    private var footerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            if shouldShowCamera {
                HomeCameraPanel(webcamManager: webcamManager)
                    .frame(width: 176)
                    .environmentObject(vm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct HomeCalendarPanel: View {
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        CalendarView()
            .frame(maxWidth: .infinity)
            .onHover { isHovering in
                vm.isHoveringCalendar = isHovering
            }
            .frame(height: homeWidgetCardHeight, alignment: .topLeading)
            .padding(12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .clipped()
    }
}

private struct HomeDisabledWidgetCard: View {
    let title: String
    let subtitle: String
    let message: String

    var body: some View {
        HomeWidgetCard(title: title, subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
    }
}

private struct HomeCameraPanel: View {
    @EnvironmentObject var vm: BoringViewModel
    let webcamManager: WebcamManager

    var body: some View {
        CameraPreviewView(webcamManager: webcamManager)
            .scaledToFit()
            .padding(8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(
                .interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0),
                value: webcamManager.cameraAvailable
            )
    }
}

private struct HomeWeatherCard: View {
    @Default(.weatherCity) private var weatherCity
    @Default(.weatherLocationMode) private var weatherLocationMode

    @ObservedObject private var manager = WeatherManager.shared

    var body: some View {
        HomeWidgetCard(
            title: "天气",
            subtitle: subtitle
        ) {
            if let snapshot = manager.snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        HomeWeatherIcon(symbolName: snapshot.current.symbolName, size: 38)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(Int(snapshot.current.temperature.rounded()))\(snapshot.current.unitSymbol)")
                                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                                Text(snapshot.current.condition)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            if let high = snapshot.current.highTemperature, let low = snapshot.current.lowTemperature {
                                Text("最高 \(Int(high.rounded()))\(snapshot.current.unitSymbol)  最低 \(Int(low.rounded()))\(snapshot.current.unitSymbol)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    if !snapshot.hourly.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(snapshot.hourly.prefix(3)) { entry in
                                HomeWeatherHour(entry: entry)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        compactMetric("体感", "\(Int(snapshot.current.feelsLike.rounded()))\(snapshot.current.unitSymbol)")
                        compactMetric("湿度", "\(snapshot.current.humidity)%")
                        compactMetric("风速", "\(Int(snapshot.current.windSpeed.rounded())) \(snapshot.current.windUnit)")
                    }

                    HStack(spacing: 8) {
                        actionButton("刷新", systemImage: "arrow.clockwise") {
                            Task {
                                await manager.refreshWeather(force: true)
                            }
                        }

                        if manager.locationAuthorizationStatus == .denied || manager.locationAuthorizationStatus == .restricted {
                            actionButton("设置", systemImage: "location.slash") {
                                manager.openLocationSettings()
                            }
                        }
                    }
                }
            } else if manager.isRefreshing {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在获取最新天气...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(manager.lastError ?? "天气暂时不可用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        if weatherLocationMode == .automatic && manager.locationAuthorizationStatus == .notDetermined {
                            actionButton("允许定位", systemImage: "location") {
                                Task {
                                    await manager.requestLocationAuthorization()
                                }
                            }
                        } else if !manager.locationServicesEnabled {
                            actionButton("设置", systemImage: "location.slash") {
                                manager.openLocationSettings()
                            }
                        } else if weatherLocationMode == .automatic &&
                            (manager.locationAuthorizationStatus == .denied || manager.locationAuthorizationStatus == .restricted)
                        {
                            actionButton("设置", systemImage: "location.slash") {
                                manager.openLocationSettings()
                            }
                        } else {
                            actionButton("刷新", systemImage: "arrow.clockwise") {
                                Task {
                                    await manager.refreshWeather(force: true)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            manager.refreshLocationAccessState()
        }
    }

    private var subtitle: String {
        if let locationName = manager.snapshot?.locationName, !locationName.isEmpty {
            return shortLocationName(from: locationName)
        }

        if weatherLocationMode == .automatic {
            return "当前位置"
        }

        let trimmedCity = weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        return shortLocationName(from: trimmedCity.isEmpty ? defaultWeatherCityName() : trimmedCity)
    }

    private func shortLocationName(from locationName: String) -> String {
        locationName
            .split(separator: ",")
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? locationName
    }
}

private struct HomeWeatherHour: View {
    let entry: WeatherSnapshot.HourlyEntry

    var body: some View {
        VStack(spacing: 5) {
            Text(entry.timeLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HomeWeatherIcon(symbolName: entry.symbolName, size: 24, cornerRadius: 6)
            Text("\(Int(entry.temperature.rounded()))\(entry.unitSymbol)")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HomeWeatherIcon: View {
    let symbolName: String
    let size: CGFloat
    var cornerRadius: CGFloat = 9

    var body: some View {
        let palette = homeWeatherSymbolPalette(for: symbolName)

        Image(systemName: symbolName)
            .symbolRenderingMode(.palette)
            .font(.system(size: size * 0.58, weight: .semibold))
            .foregroundStyle(palette.primary, palette.secondary)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [
                        palette.primary.opacity(0.22),
                        palette.secondary.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private func homeWeatherSymbolPalette(for symbolName: String) -> (primary: Color, secondary: Color) {
    if symbolName.contains("sun") {
        return (.yellow, .orange)
    }
    if symbolName.contains("moon") {
        return (.indigo, .cyan)
    }
    if symbolName.contains("bolt") {
        return (.yellow, .purple)
    }
    if symbolName.contains("snow") {
        return (.cyan, .blue)
    }
    if symbolName.contains("rain") || symbolName.contains("drizzle") {
        return (.cyan, .blue)
    }
    if symbolName.contains("fog") {
        return (.gray, .white.opacity(0.8))
    }
    return (.gray, .blue)
}

private struct HomePomodoroCard: View {
    @ObservedObject private var manager = PomodoroManager.shared

    var body: some View {
        HomeWidgetCard(
            title: "Pomodoro",
            subtitle: manager.phase.rawValue
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(manager.formattedRemaining)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                ProgressView(value: manager.progress)
                    .progressViewStyle(.linear)
                    .tint(accentColor(for: manager.phase))

                HStack(spacing: 8) {
                    compactMetric("Next", manager.nextPhaseTitle)
                    compactMetric("Session", manager.currentCycleIndexLabel)
                    compactMetric("Done", "\(manager.completedFocusSessions)")
                }

                HStack(spacing: 8) {
                    actionButton(
                        manager.isRunning ? "Pause" : "Start",
                        systemImage: manager.isRunning ? "pause.fill" : "play.fill",
                        prominent: true,
                        tint: accentColor(for: manager.phase)
                    ) {
                        manager.toggleRunning()
                    }

                    iconOnlyAction("forward.fill", help: "Skip phase") {
                        manager.skipPhase()
                    }

                    iconOnlyAction("arrow.counterclockwise", help: "Reset phase") {
                        manager.resetCurrentPhase()
                    }
                }
            }
        }
    }

    private func accentColor(for phase: PomodoroPhase) -> Color {
        switch phase {
        case .focus:
            return .effectiveAccent
        case .shortBreak:
            return .green
        case .longBreak:
            return .orange
        }
    }
}

private struct QuickLaunchHomeCard: View {
    @ObservedObject private var manager = QuickLaunchManager.shared

    let apps: [QuickLaunchAppItem]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        HomeWidgetCard(
            title: "Quick launch",
            subtitle: "Apps"
        ) {
            if apps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add apps in Settings > General.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    actionButton("Open settings", systemImage: "slider.horizontal.3") {
                        SettingsWindowController.shared.showWindow()
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(apps.prefix(6))) { item in
                            Button {
                                manager.open(item)
                            } label: {
                                VStack(spacing: 6) {
                                    AppIcon(for: item)
                                        .resizable()
                                        .frame(width: 30, height: 30)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    Text(item.displayName)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let lastError = manager.lastError, !lastError.isEmpty {
                        Text(lastError)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

private struct HomeMediaCard: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging = false
    @State private var lastDragged = Date.distantPast

    var body: some View {
        HomeWidgetCard(
            title: "Media",
            subtitle: musicManager.isPlaying ? "Playing" : "Controls"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    mediaArtwork

                    VStack(alignment: .leading, spacing: 3) {
                        Text(musicManager.songTitle.isEmpty ? "Not playing" : musicManager.songTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(musicManager.artistName.isEmpty ? activeSourceLabel : musicManager.artistName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer(minLength: 0)
                }

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
                }
                .frame(height: 26)

                HStack(spacing: 8) {
                    mediaButton("backward.fill") {
                        MusicManager.shared.previousTrack()
                    }
                    mediaButton(musicManager.isPlaying ? "pause.fill" : "play.fill", prominent: true) {
                        MusicManager.shared.togglePlay()
                    }
                    mediaButton("forward.fill") {
                        MusicManager.shared.nextTrack()
                    }
                    mediaButton("music.note") {
                        MusicManager.shared.openMusicApp()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                if Defaults[.enableLyrics], musicManager.isPlaying {
                    Text(currentLyricLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var mediaArtwork: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    if !musicManager.isPlaying {
                        Color.black.opacity(0.42)
                    }
                }

            if !musicManager.usingAppIconForArtwork {
                AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .offset(x: 4, y: 4)
            }
        }
        .frame(width: 52, height: 52)
    }

    private var activeSourceLabel: String {
        Defaults[.mediaController].rawValue
    }

    private var currentLyricLine: String {
        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Lyrics enabled" : trimmed.replacingOccurrences(of: "\n", with: " ")
    }

    private func mediaButton(
        _ systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: prominent ? 16 : 13, weight: .semibold))
                .frame(width: prominent ? 44 : 36, height: 32)
                .background(Color.white.opacity(prominent ? 0.12 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct HomeWidgetCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            content
        }
        .frame(maxWidth: .infinity, minHeight: homeWidgetCardHeight, maxHeight: homeWidgetCardHeight, alignment: .topLeading)
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipped()
    }
}

private func compactMetric(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        Text(value)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .background(Color.white.opacity(0.05))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
}

private func actionButton(
    _ title: String,
    systemImage: String,
    prominent: Bool = false,
    tint: Color? = nil,
    action: @escaping () -> Void
) -> some View {
    Group {
        if prominent {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
        }
    }
    .tint(tint)
    .controlSize(.small)
}

private func iconOnlyAction(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: systemImage)
            .frame(width: 22)
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .help(help)
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
