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
                if active {
                    Text(item.label)
                        .font(.system(size: 9, weight: .bold))
                        .fixedSize()
                }
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
        HStack(spacing: 4) {
            Image(systemName: sound.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 12)
            Slider(value: $sound.volume, in: 0...1)
                .controlSize(.mini)
                .tint(accent)
                .frame(width: 52)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}
