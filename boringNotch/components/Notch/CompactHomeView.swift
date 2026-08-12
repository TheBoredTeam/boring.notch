//
//  CompactHomeView.swift
//  boringNotch
//
//  A smaller open-notch layout: just the now-playing essentials — art,
//  title, scrubber, transport — with no tab bar, calendar or mirror.
//
//  Deliberately built on the same pieces the full layout uses
//  (MusicSliderView, HoverButton, MarqueeText, the musicControlSlots
//  preference) rather than a parallel implementation, so a fix to seeking
//  or the control slots applies to both layouts instead of drifting.
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

    private let artSize: CGFloat = 56

    var body: some View {
        if musicManager.isPlayerIdle && !musicManager.isPlaying {
            idleState
        } else {
            VStack(spacing: 8) {
                header
                MusicSliderView(
                    sliderValue: $sliderValue,
                    duration: $musicManager.songDuration,
                    lastDragged: $lastDragged,
                    color: musicManager.avgColor,
                    dragging: $dragging,
                    currentDate: Date(),
                    timestampDate: musicManager.timestampDate,
                    elapsedTime: musicManager.elapsedTime,
                    playbackRate: musicManager.playbackRate,
                    isPlaying: musicManager.isPlaying
                ) { newValue in
                    MusicManager.shared.seek(to: newValue)
                }
                .frame(height: 24)
                transport
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                .frame(width: artSize, height: artSize)

            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 1) {
                    Spacer(minLength: 0)
                    MarqueeText(
                        musicManager.songTitle,
                        font: .system(size: 13, weight: .semibold),
                        color: .white,
                        frameWidth: geo.size.width
                    )
                    MarqueeText(
                        musicManager.artistName,
                        font: .system(size: 11),
                        color: playerColorTinting
                            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                            : .gray,
                        frameWidth: geo.size.width
                    )
                    Spacer(minLength: 0)
                }
            }
            .frame(height: artSize)

            // AudioSpectrumView tints itself, so no outer gradient/mask —
            // that would just fight the colour it already applies.
            if !musicManager.isPlayerIdle {
                AudioSpectrumView(
                    isPlaying: musicManager.isPlaying,
                    tintColor: coloredSpectrogram
                        ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                        : .gray
                )
                .frame(width: 18, height: 14)
                .frame(height: artSize)
            }
        }
    }

    /// Same slot preference as the full layout, so the buttons a user
    /// configured there are the ones they get here.
    private var transport: some View {
        // Pad/trim to the configured slot count locally — NotchHomeView's
        // `padded` helper is fileprivate to that file, and widening its
        // access just for this would be a worse trade than four lines here.
        let count = min(max(slotLimit, MusicControlButton.minSlotCount), MusicControlButton.maxSlotCount)
        var slots = slotConfig
        if slots.count < count {
            slots += Array(repeating: .none, count: count - slots.count)
        }
        slots = Array(slots.prefix(count))

        return HStack(spacing: 4) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
            // Slots that only make sense in the full layout (mirror,
            // calendar, and anything added later) are skipped rather than
            // rendered half-working in a player-only view.
            EmptyView()
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .one: "repeat.1"
        default: "repeat"
        }
    }

    private var repeatIconColor: Color {
        musicManager.repeatMode == .off ? .primary : .red
    }

    private var idleState: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.gray)
            Text("Nothing playing")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
