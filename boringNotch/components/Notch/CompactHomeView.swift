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
//  MarqueeText and the musicControlSlots preference rather than porting
//  Atoll's ~1500-line view wholesale, so seeking and the configured
//  transport buttons stay identical between the two layouts instead of
//  drifting apart.
//

import Defaults
import SwiftUI

struct CompactHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID

    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast

    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.playerColorTinting) private var playerColorTinting

    private let albumArtWidth: CGFloat = 50
    private let headerSpacing: CGFloat = 10
    /// Matches the trailing time label's width in the row below, so the
    /// visualizer's bars sit centred over "-0:00" rather than drifting.
    private let vizBlockWidth: CGFloat = 42
    private let vizBarWidth: CGFloat = 24

    var body: some View {
        if !musicManager.isPlaying && musicManager.isPlayerIdle {
            idleState
        } else {
            VStack(spacing: 0) {
                header
                    .frame(height: albumArtWidth)

                progressRow
                    .padding(.top, 6)

                transport
                    .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Header

    private var header: some View {
        GeometryReader { geo in
            let textWidth = max(
                0,
                geo.size.width - albumArtWidth - headerSpacing - (vizBlockWidth + headerSpacing)
            )

            HStack(alignment: .center, spacing: headerSpacing) {
                AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                    .frame(width: albumArtWidth, height: albumArtWidth)

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
                    AudioSpectrumView(
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

    /// Uses the same slot preference as the full layout, so the buttons
    /// configured there are the ones that appear here.
    private var transport: some View {
        HStack(spacing: 10) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var displayedSlots: [MusicControlButton] {
        // Padding is done here rather than via NotchHomeView's `padded`
        // helper, which is fileprivate to that file.
        let count = min(max(slotLimit, MusicControlButton.minSlotCount), MusicControlButton.maxSlotCount)
        var slots = slotConfig
        if slots.count < count {
            slots += Array(repeating: .none, count: count - slots.count)
        }
        return Array(slots.prefix(count))
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
        case .none:
            EmptyView()
        default:
            // Slots that only make sense in the full layout are skipped
            // rather than rendered half-working in a player-only view.
            EmptyView()
        }
    }

    private var repeatIcon: String {
        musicManager.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private var repeatIconColor: Color {
        musicManager.repeatMode == .off ? .primary : .red
    }

    private var idleState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.slash")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.gray)
            Text("Nothing Playing")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
