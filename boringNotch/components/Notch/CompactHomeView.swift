// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

//
//  CompactHomeView.swift
//  boringNotch
//
//  A smaller open-notch layout: just the now-playing essentials — art,
//  title, scrubber, transport. The host places tabs below the opened notch.
//
//  Layout and proportions follow Atoll's MinimalisticMusicPlayerView
//  (https://github.com/Ebullioscopic/Atoll, GPL-3.0, itself a boring.notch
//  fork): 50pt album art, 12/10pt title and artist, a fixed-width
//  visualizer block on the right sized to match the trailing time label so
//  the bars centre over it, a progress row, and a transport row.
//
//  Seeking and transport use the main app's existing MusicSliderView and
//  MusicManager APIs. The user's configured control slots remain available.
//

import Defaults
import SwiftUI

struct CompactHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    let albumArtNamespace: Namespace.ID
    var horizontalMediaGestureFeedback: CGFloat = 0

    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast

    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
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
                .padding(.top, 3)

            transport
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        // Atoll's 15/3 formula assumes the player is the whole panel; here
        // a notch-clearance spacer sits above it, so these are trimmed to
        // land the panel at the intended overall height. The 2pt bottom pad
        // keeps the play/pause's hover fill from kissing the rounded corner
        // without adding a visible band of empty space.
        .padding(.top, 4)
        .padding(.bottom, 2)
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
                        $musicManager.songTitle,
                        font: .system(size: 12, weight: .semibold),
                        nsFont: .caption1,
                        textColor: .white,
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
                    Rectangle()
                        .fill(coloredSpectrogram
                            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                            : .gray)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                        }
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
                    isForNotification: false
                )
                .offset(y: -14)
            }
        }
    }

    // MARK: - Progress

    private var progressRow: some View {
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
                isPlaying: musicManager.isPlaying,
                onValueChange: { MusicManager.shared.seek(to: $0) }
            )
            .padding(.top, 5)
            .frame(height: 36)
        }
        .onAppear { sliderValue = musicManager.elapsedTime }
    }

    // MARK: - Transport

    /// Apply the same slot limit and ordering as the main player.
    private var displayedSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig + Array(repeating: MusicControlButton.none,
                                        count: max(0, sanitizedLimit - slotConfig.count))
        return Array(padded.prefix(sanitizedLimit))
    }

    private var transport: some View {
        HStack(spacing: 6) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                control(for: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func control(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                musicManager.toggleShuffle()
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium) { musicManager.previousTrack() }
        case .playPause:
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                musicManager.togglePlay()
            }
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium) { musicManager.nextTrack() }
        case .repeatMode:
            HoverButton(icon: musicManager.repeatMode == .one ? "repeat.1" : "repeat",
                        iconColor: musicManager.repeatMode == .off ? .primary : .red, scale: .medium) {
                musicManager.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            HoverButton(icon: "gobackward.15", scale: .medium) { musicManager.skip(seconds: -15) }
        case .goForward:
            HoverButton(icon: "goforward.15", scale: .medium) { musicManager.skip(seconds: 15) }
        case .none:
            Color.clear.frame(height: 1)
        }
    }

    private var compactAlbumArt: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: musicManager.albumArt)
                .resizable().scaledToFill()
                .frame(width: albumArtWidth, height: albumArtWidth)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Badge scaled to this art. AlbumArtView's is a fixed 30pt with
            // a +10/+10 offset, sized for the 120pt art in the full layout —
            // on 50pt art it spills outside the corner.
            if !musicManager.usingAppIconForArtwork {
                AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                    .resizable().scaledToFit()
                    .frame(width: 18, height: 18)
                    .offset(x: 5, y: 5)
            }
        }
        .frame(width: albumArtWidth, height: albumArtWidth)
    }
}
