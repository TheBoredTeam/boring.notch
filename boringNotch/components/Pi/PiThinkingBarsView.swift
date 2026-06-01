//
//  PiThinkingBarsView.swift
//  boringNotch
//
//  Equalizer-style "thinking" bars for a running Pi turn. Reuses the now-playing
//  AudioSpectrum so the Pi peek reads visually like a song. Under Reduce Motion the
//  bars hold static (no looping animation), per the motion spec.
//

import SwiftUI

struct PiThinkingBarsView: View {
    let isActive: Bool
    /// Bar color. Defaults to white (the open Pi tab); the peek passes the toolkit accent.
    var tint: NSColor = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AudioSpectrumView(isPlaying: .constant(isActive && !reduceMotion), tint: tint)
            .frame(width: 16, height: 12)
            // Active → full; reduce-motion → dim static bars; idle → hidden.
            .opacity(isActive ? 1 : (reduceMotion ? 0.5 : 0))
            .accessibilityHidden(true)
    }
}
