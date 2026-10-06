//
//  ContentView+SneakPeek.swift
//  boringNotch
//
//  Sneak peek state for the closed notch, including the optional
//  always-visible song title.
//

import Defaults
import SwiftUI

extension ContentView {
    /// "Always show sneak peek": keep the song title visible for as long as the
    /// music live activity is on screen, instead of only after a song change.
    var showingPersistentMusicPeek: Bool {
        Defaults[.sneakPeekAlwaysVisible]
            && vm.notchState == .closed
            && !vm.hideOnClosed
            && !coordinator.expandingView.show
            && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled
            && notificationManager.activeNotification == nil
    }

    /// The standard-style peek drawn as a line under the closed notch.
    var showingPersistentStandardPeek: Bool {
        showingPersistentMusicPeek
            && Defaults[.sneakPeekStyles] == .standard
            && !coordinator.shouldShowSneakPeek(on: vm.screenUUID)
    }

    /// Whether the closed notch shows a peek line under it: a standard-style
    /// music peek (temporary or always visible), or any non-music sneak peek.
    var showingStandardPeekLine: Bool {
        guard vm.notchState == .closed else { return false }
        if showingPersistentStandardPeek { return true }
        guard coordinator.shouldShowSneakPeek(on: vm.screenUUID) else { return false }
        guard coordinator.sneakPeekState(for: vm.screenUUID).type == .music else { return true }
        return !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard
    }

    func standardMusicPeek() -> some View {
        HStack(alignment: .center) {
            Image(systemName: "music.note")
            GeometryReader { geo in
                MarqueeText(
                    musicManager.songTitle + " - " + musicManager.artistName,
                    color: Defaults[.playerColorTinting]
                        ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                        : .gray,
                    delayDuration: 1.0,
                    frameWidth: geo.size.width,
                    // Always visible: scroll once per song rather than forever.
                    loops: !showingPersistentStandardPeek
                )
            }
        }
        .foregroundStyle(.gray)
        .padding(.bottom, 10)
    }
}
