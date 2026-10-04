//
//  AmbientSoundBar.swift
//  boringNotch
//
//  Compact focus-sound picker for the Pomodoro tab: a horizontally scrolling
//  strip of icon chips plus an inline volume slider that appears while playing.
//

import SwiftUI

struct AmbientSoundBar: View {
    var accent: Color
    @ObservedObject private var sound = AmbientSoundManager.shared

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(AmbientSoundManager.Sound.allCases) { item in
                        chip(item)
                    }
                }
                .padding(.vertical, 1)
            }

            if sound.current != nil {
                volumeControl
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.snappy(duration: 0.2), value: sound.current)
    }

    private func chip(_ item: AmbientSoundManager.Sound) -> some View {
        let active = sound.current == item
        return Button {
            sound.toggle(item)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(item.label)
                    .font(.system(size: 9, weight: active ? .bold : .medium))
                    .fixedSize()
            }
            .foregroundColor(active ? .black : .white.opacity(0.6))
            .frame(height: 22)
            .padding(.horizontal, active ? 9 : 7)
            .background(
                Capsule().fill(active ? accent : Color.white.opacity(0.08))
            )
            .overlay(
                active && item.isStream
                    ? Capsule().stroke(Color.black.opacity(0.15), lineWidth: 1)
                    : nil
            )
        }
        .buttonStyle(.plain)
        .help(item.isStream ? "\(item.label) — streams over the network" : item.label)
    }

    private var volumeControl: some View {
        HStack(spacing: 5) {
            Button {
                // One-tap mute / restore.
                sound.volume = sound.volume < 0.01 ? 0.6 : 0
            } label: {
                Image(systemName: sound.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            // Narrower than before (was 130pt) — it was eating enough width to
            // crowd the chip strip, leaving fewer sound chips visible without
            // scrolling. A precise drag-anywhere track still works fine narrow.
            VolumeSlider(value: $sound.volume, accent: accent)
                .frame(width: 46, height: 18)

            Text("\(Int((sound.volume * 100).rounded()))%")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 26, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 7)
        .frame(height: 28)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

/// A precise volume track: a tall hit area, visible fill + thumb, and
/// drag-anywhere control so small movements map to small changes even at a
/// narrow width.
private struct VolumeSlider: View {
    @Binding var value: Double
    var accent: Color
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let trackH: CGFloat = 5
            let thumb: CGFloat = dragging ? 14 : 11
            let clamped = max(0, min(1, value))
            let fillW = CGFloat(clamped) * w

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                    .frame(height: trackH)
                Capsule().fill(accent)
                    .frame(width: max(trackH, fillW), height: trackH)
                Circle()
                    .fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: min(max(fillW - thumb / 2, 0), w - thumb))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        dragging = true
                        value = Double(max(0, min(1, g.location.x / w)))
                    }
                    .onEnded { _ in dragging = false }
            )
            .animation(.snappy(duration: 0.12), value: dragging)
        }
    }
}
