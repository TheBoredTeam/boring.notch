//
//  LockScreenMediaWidgetView.swift
//  boringNotch
//

import SwiftUI

struct LockScreenMediaWidgetView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @State private var progressValue: Double = 0
    @State private var isAdjustingProgress = false

    private var duration: Double {
        max(musicManager.songDuration, 1)
    }

    private var progress: Binding<Double> {
        Binding(
            get: {
                if isAdjustingProgress {
                    return min(max(progressValue, 0), duration)
                }
                return min(max(musicManager.estimatedPlaybackPosition(), 0), duration)
            },
            set: { progressValue = min(max($0, 0), duration) }
        )
    }

    private var title: String {
        musicManager.songTitle.isEmpty
            ? LockScreenText.value("Not Playing", "未在播放")
            : musicManager.songTitle
    }

    var body: some View {
        LockScreenWidgetCard(cornerRadius: 26) {
            HStack(spacing: 12) {
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(musicManager.artistName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Slider(value: progress, in: 0...duration, onEditingChanged: progressEditingChanged)
                        .controlSize(.small)
                        .tint(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 7) {
                    mediaButton(systemName: "backward.fill", label: LockScreenText.value("Previous track", "上一首")) {
                        musicManager.previousTrack()
                    }

                    mediaButton(
                        systemName: musicManager.isPlaying ? "pause.fill" : "play.fill",
                        label: musicManager.isPlaying
                            ? LockScreenText.value("Pause", "暂停")
                            : LockScreenText.value("Play", "播放")
                    ) {
                        musicManager.togglePlay()
                    }

                    mediaButton(systemName: "forward.fill", label: LockScreenText.value("Next track", "下一首")) {
                        musicManager.nextTrack()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: 360, height: 108)
        }
    }

    private func progressEditingChanged(_ isEditing: Bool) {
        if isEditing {
            progressValue = min(max(musicManager.estimatedPlaybackPosition(), 0), duration)
            isAdjustingProgress = true
        } else {
            isAdjustingProgress = false
            musicManager.seek(to: progressValue)
        }
    }

    private func mediaButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(label)
    }
}
