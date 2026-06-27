//
//  UnlockAnimation.swift
//  boringNotch
//
//  A one-shot lock → open morph that plays in the notch when the Mac is unlocked.
//  Uses native SF Symbol transitions (no image assets), tinted with the app accent.
//

import SwiftUI

struct UnlockAnimation: View {
    /// When false, render the lock fully visible (closed) with no timeline — the static
    /// "locked, closed padlock over the lock screen" state.
    var autoPlay: Bool
    /// Unlock flow: skip the pop-in + initial hold and morph closed → open right away
    /// (the lock was already shown closed over the lock screen).
    var immediate: Bool
    /// Called when the unlock animation has fully played out so the caller can clear its flag.
    var onFinish: () -> Void

    @State private var unlocked: Bool = false
    @State private var appeared: Bool

    init(autoPlay: Bool = true, immediate: Bool = false, onFinish: @escaping () -> Void = {}) {
        self.autoPlay = autoPlay
        self.immediate = immediate
        self.onFinish = onFinish
        // Already-visible cases (the unlock morph after the locked lock, or the pure static
        // closed lock) skip the pop-in so the handoff is seamless.
        _appeared = State(initialValue: immediate || !autoPlay)
    }

    var body: some View {
        // A SINGLE Image expression (ternary on systemName) keeps view identity so the
        // .replace transition morphs the glyph instead of hard-cutting. Do not add .id().
        Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.effectiveAccent)
            .contentTransition(.symbolEffect(.replace))   // the closed → open morph
            .symbolEffect(.bounce, value: unlocked)        // little flourish on the flip
            .scaleEffect(appeared ? 1.0 : 0.6)
            .opacity(appeared ? 1.0 : 0.0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                guard autoPlay else { return }
                if immediate {
                    try? await Task.sleep(for: .seconds(0.15))
                } else {
                    // Desktop flow: pop in, hold closed.
                    withAnimation(StandardAnimations.bouncy) { appeared = true }
                    try? await Task.sleep(for: .seconds(0.45))
                }

                // Morph to open (the swap must be inside withAnimation).
                withAnimation(.easeInOut(duration: 0.35)) { unlocked = true }

                // Hold open, then fade out and finish.
                try? await Task.sleep(for: .seconds(0.9))
                withAnimation(.easeOut(duration: 0.3)) { appeared = false }
                try? await Task.sleep(for: .seconds(0.3))
                onFinish()
            }
    }
}

#Preview {
    UnlockAnimation(onFinish: {})
        .frame(width: 185, height: 32)
        .background(.black)
}
