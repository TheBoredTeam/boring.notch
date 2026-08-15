//
//  CompactHomeView.swift
//  boringNotch
//
//  A smaller open-notch layout: just the now-playing essentials — art,
//  title, scrubber, transport — with no tab bar, calendar or mirror.
//
//  Layout and proportions follow Atoll's MinimalisticMusicPlayerView
//  (https://github.com/Ebullioscopic/Atoll, GPL-3.0, itself a boring.notch
//  fork): 50pt album art, 12/10pt title and artist, a fixed-width
//  visualizer block on the right sized to match the trailing time label so
//  the bars centre over it, an inline progress row with a counting-down
//  remaining time, and a 10pt-spaced transport row.
//
//  Built on this project's own MusicSliderView / HoverButton /
//  MarqueeText rather than porting Atoll's ~1500-line view wholesale, so
//  seeking behaves identically in both layouts instead of drifting apart.
//  The transport row is a fixed five here rather than the musicControlSlots
//  preference — that preference exists to configure the full layout, and
//  its default would leave compact mode without shuffle or media output.
//

import Defaults
import SwiftUI

struct CompactHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    let albumArtNamespace: Namespace.ID

    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @State private var showingOutputPicker = false
    @ObservedObject private var routeManager = AudioRouteManager.shared

    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.playerColorTinting) private var playerColorTinting

    private let albumArtWidth: CGFloat = 45
    private let headerSpacing: CGFloat = 10
    /// Matches the trailing time label's width in the row below, so the
    /// visualizer's bars sit centred over "-0:00" rather than drifting.
    private let vizBlockWidth: CGFloat = 42
    private let vizBarWidth: CGFloat = 24

    // No idle branch, deliberately. The standard layout has none either —
    // it renders whatever MusicManager last cached, so a paused or stopped
    // track keeps its art, title and scrub position. A "Nothing Playing"
    // placeholder here made compact mode lose state the full layout keeps.
    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: albumArtWidth)

            progressRow
                .padding(.top, 4)

            transport
                .padding(.top, 1)
        }
        .padding(.horizontal, 12)
        // Atoll's 15/3 formula assumes the player is the whole panel; here
        // a notch-clearance spacer sits above it, so these are trimmed to
        // land the panel at the intended overall height.
        .padding(.top, 4)
        .padding(.bottom, 1)
        .frame(maxWidth: .infinity)
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Header

    private var header: some View {
        GeometryReader { geo in
            let textWidth = max(
                0,
                geo.size.width - albumArtWidth - headerSpacing - (vizBlockWidth + headerSpacing)
            )

            HStack(alignment: .center, spacing: headerSpacing) {
                compactAlbumArt

                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(
                        musicManager.songTitle,
                        font: .system(size: 12, weight: .semibold),
                        color: .white,
                        frameWidth: textWidth
                    )

                    Text(musicManager.artistName)
                        .font(.system(size: 10))
                        .foregroundStyle(
                            playerColorTinting
                                ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                                : .gray
                        )
                        .lineLimit(1)
                }
                .frame(width: textWidth, alignment: .leading)

                ZStack {
                    MusicVisualizer(
                        isPlaying: musicManager.isPlaying,
                        tintColor: coloredSpectrogram
                            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                            : .gray
                    )
                    .frame(width: vizBarWidth, height: 16)
                }
                .frame(width: vizBlockWidth)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Compact mode hides BoringHeader (it spans the full notch
            // width), which took the battery with it. Overlaid rather than
            // placed in the HStack so it doesn't steal width from the title.
            if Defaults[.showBatteryIndicator] {
                BoringBatteryView(
                    batteryWidth: 24,
                    isCharging: batteryModel.isCharging,
                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                    isPluggedIn: batteryModel.isPluggedIn,
                    levelBattery: batteryModel.levelBattery,
                    maxCapacity: batteryModel.maxCapacity,
                    timeToFullCharge: batteryModel.timeToFullCharge,
                    timeToDischarge: batteryModel.timeToDischarge,
                    maxAdapterWatts: batteryModel.maxAdapterWatts,
                    isForNotification: false
                )
                .offset(y: -14)
            }
        }
    }

    // MARK: - Progress

    private var progressRow: some View {
        // See NotchHomeView.musicSlider — 0.5s ticks are imperceptible here.
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.5 : nil)) { timeline in
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
                isPlaying: musicManager.isPlaying,
                onValueChange: { MusicManager.shared.seek(to: $0) },
                labelLayout: .inline,
                trailingLabel: .remaining,
                restingTrackHeight: 7,
                draggingTrackHeight: 11
            )
        }
        .onAppear { sliderValue = musicManager.elapsedTime }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 10) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: playPauseSize)
    }

    /// Atoll's control dimensions: 36pt secondary buttons with 18pt glyphs,
    /// a 54pt play/pause with a 26pt glyph. HoverButton's 30/40 is what made
    /// this row read undersized against the rest of the panel.
    private let controlSize: CGFloat = 32
    private let playPauseSize: CGFloat = 48

    private func compactControl(
        icon: String,
        size: CGFloat,
        glyph: CGFloat,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        CompactControlButton(
            icon: icon,
            frameSize: size,
            glyphSize: glyph,
            tint: tint,
            action: action
        )
    }

    /// Fixed five rather than the musicControlSlots preference, so compact
    /// mode always shows the full transport regardless of how the standard
    /// layout is configured.
    private var displayedSlots: [MusicControlButton] {
        [.shuffle, .previous, .playPause, .next, .mediaOutput]
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            compactControl(
                icon: "shuffle",
                size: controlSize,
                glyph: 16,
                tint: musicManager.isShuffled ? .red : .white
            ) { MusicManager.shared.toggleShuffle() }
        case .previous:
            compactControl(icon: "backward.fill", size: controlSize, glyph: 16) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            compactControl(
                icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
                size: playPauseSize,
                glyph: 23
            ) { MusicManager.shared.togglePlay() }
        case .next:
            compactControl(icon: "forward.fill", size: controlSize, glyph: 16) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            compactControl(icon: repeatIcon, size: controlSize, glyph: 16, tint: repeatIconColor) {
                MusicManager.shared.toggleRepeat()
            }
        case .mediaOutput:
            mediaOutputButton
        case .none:
            EmptyView()
        default:
            // Slots that only make sense in the full layout are skipped
            // rather than rendered half-working in a player-only view.
            EmptyView()
        }
    }

    /// Shows where audio is going and switches it, via a popover device
    /// picker.
    private var mediaOutputButton: some View {
        compactControl(icon: routeSymbol, size: controlSize, glyph: 16) {
            // Enumerate on open rather than polling: devices come and go
            // (AirPods connecting, a display waking) and a list built at
            // launch would be stale by the time anyone opened it.
            routeManager.refreshDevices()
            showingOutputPicker.toggle()
        }
        .popover(isPresented: $showingOutputPicker, arrowEdge: .bottom) {
            AudioOutputPicker(
                routeManager: routeManager,
                onSelect: { showingOutputPicker = false }
            )
        }
    }

    private var compactAlbumArt: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: albumArtWidth, height: albumArtWidth)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Badge scaled to this art. AlbumArtView's is a fixed 30pt with
            // a +10/+10 offset, sized for the 120pt art in the full layout —
            // on 50pt art it spills outside the corner.
            if !musicManager.usingAppIconForArtwork {
                appIcon(for: musicManager.bundleIdentifier ?? MediaAppBundleID.appleMusic)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .offset(x: 5, y: 5)
            }
        }
        .frame(width: albumArtWidth, height: albumArtWidth)
    }

    /// Prefer the live device's own icon; fall back to the resolver's
    /// classification before the first enumeration has run.
    private var routeSymbol: String {
        routeManager.activeDevice?.iconName ?? AudioOutputRouteResolver.shared.outputRouteSymbol()
    }

    private var repeatIcon: String {
        musicManager.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private var repeatIconColor: Color {
        musicManager.repeatMode == .off ? .primary : .red
    }

}

/// Output device list for the compact player's media-output button.
struct AudioOutputPicker: View {
    @ObservedObject var routeManager: AudioRouteManager
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Output")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if routeManager.devices.isEmpty {
                // Enumeration is async, so an empty list on first open is
                // normal rather than an error worth alarming anyone about.
                Text("Looking for devices…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else {
                ForEach(routeManager.devices) { device in
                    Button {
                        routeManager.select(device)
                        onSelect()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: device.iconName)
                                .frame(width: 18)
                            Text(device.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer(minLength: 12)
                            if device.id == routeManager.activeDeviceID {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 6)
            }
        }
        .frame(minWidth: 220)
    }
}

/// Transport button matching Atoll's MinimalisticSquircircleButton: a
/// squircle that fills faintly on hover, sized independently of its glyph
/// so a 54pt play/pause and a 36pt skip share the same visual language.
///
/// Not HoverButton — that's fixed at 30/40pt with a capsule fill, which
/// reads undersized against this layout's 50pt artwork.
private struct CompactControlButton: View {
    let icon: String
    let frameSize: CGFloat
    let glyphSize: CGFloat
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: frameSize * 0.4, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.12) : .clear)
                .frame(width: frameSize, height: frameSize)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: glyphSize, weight: .medium))
                        .foregroundStyle(tint)
                        .contentTransition(.symbolEffect(.replace))
                }
                .contentShape(RoundedRectangle(cornerRadius: frameSize * 0.4, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
    }
}

/// Audio-output slot for the standard layout's control row.
///
/// Separate from CompactHomeView's inline version only because that one
/// uses the compact button sizing; the picker and behaviour are shared.
struct MediaOutputSlotButton: View {
    @ObservedObject private var routeManager = AudioRouteManager.shared
    @State private var showingPicker = false

    var body: some View {
        HoverButton(icon: routeSymbol, scale: .medium) {
            routeManager.refreshDevices()
            showingPicker.toggle()
        }
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            AudioOutputPicker(routeManager: routeManager) {
                showingPicker = false
            }
        }
    }

    private var routeSymbol: String {
        routeManager.activeDevice?.iconName ?? AudioOutputRouteResolver.shared.outputRouteSymbol()
    }
}
