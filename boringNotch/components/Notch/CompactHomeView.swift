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
    let albumArtNamespace: Namespace.ID

    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast

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

    private var transport: some View {
        HStack(spacing: 10) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Fixed five, deliberately not the musicControlSlots preference. That
    /// preference defaults to [.none, .previous, .playPause, .next, .none],
    /// which is why this row was rendering only three buttons — compact
    /// mode is meant to show shuffle and media output too.
    private var displayedSlots: [MusicControlButton] {
        [.shuffle, .previous, .playPause, .next, .none]
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
            mediaOutputButton
        default:
            // Slots that only make sense in the full layout are skipped
            // rather than rendered half-working in a player-only view.
            EmptyView()
        }
    }

    /// Shows where audio is currently going and opens Sound settings.
    ///
    /// Atoll's equivalent opens a popover that switches device inline, but
    /// that needs its AudioRouteManager (enumeration + switching), which
    /// this project doesn't have — AudioOutputRouteResolver only classifies
    /// the current route. Handing off to Sound settings is honest about
    /// that rather than faking a picker that can't switch anything.
    private var mediaOutputButton: some View {
        HoverButton(icon: routeSymbol, scale: .medium) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
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
                AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .offset(x: 5, y: 5)
            }
        }
        .frame(width: albumArtWidth, height: albumArtWidth)
    }

    private var routeSymbol: String {
        AudioOutputRouteResolver.shared.outputRouteSymbol()
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
