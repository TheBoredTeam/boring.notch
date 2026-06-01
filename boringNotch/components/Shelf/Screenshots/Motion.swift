//
//  Motion.swift
//  boringNotch
//
//  Purpose: One shared motion vocabulary for shelf interactions, following the
//           emil-design-eng + web-animation-design rules: animate only
//           transform/opacity, ease-out for feedback (instant), springs for items
//           settling in, exits ~20% faster than enters, and collapse everything to
//           a near-instant fade under Reduce Motion.
//  Layer: Support
//

import SwiftUI

enum Motion {
    // MARK: Curves (feedback — feels immediate)

    /// Hover lift affordance. ease-out-quint.
    static let hover = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.16)

    /// Press feedback — the system responding right now.
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)

    /// "Copied" flash in/out.
    static let flash = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)

    // MARK: Item lifecycle

    /// A thumbnail settling into the shelf — a touch of bounce so a new capture
    /// feels like it "drops" in.
    static let shelfItemEnter = Animation.spring(duration: 0.34, bounce: 0.18)

    /// Removal — faster than the enter, no bounce (exits beat enters).
    static let shelfItemExit = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)

    // MARK: Pi peek + panel

    /// Peek wings appearing when a run starts. Width clip-grow + opacity, ease-out-quint.
    static let peekWingEnter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.42)

    /// Peek wings retracting — exit ≈ 25% faster than the enter.
    static let peekWingExit = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.32)

    /// Peek/activity text swap, outgoing half (thinking → forming → name → ✓).
    static let textSwapOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.16)

    /// Peek/activity text swap, incoming half — slightly slower than the out.
    static let textSwapIn = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)

    /// One full shimmer sweep across forming-tool text. Linear is correct here:
    /// constant looping motion is its one legitimate use.
    static let shimmerPeriod: TimeInterval = 1.8

    /// Toolkit glow blooming behind the peek logo. Spring keeps it interruptible.
    static let glowBloom = Animation.spring(duration: 0.42, bounce: 0.15)

    /// Done-peek auto-dismiss — an exit, so faster and smaller.
    static let peekDismiss = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.25)

    /// Reduced-motion fallback for any of the above: near-instant, movement dropped.
    static let reduced = Animation.easeOut(duration: 0.12)

    // MARK: Reduce-motion resolution

    /// Returns `full` normally, or the near-instant fallback under Reduce Motion.
    static func resolved(_ full: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : full
    }

    // MARK: Transitions

    /// Shelf thumbnail enter/leave. Scale *up from* 0.92 (never from 0) plus a fade;
    /// removal is a hair smaller and rides the faster curve.
    static let thumbnail = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.92).combined(with: .opacity),
        removal: .scale(scale: 0.94).combined(with: .opacity)
    )

    /// Overlays anchored to an item (copied flash, delete button): scale from 0.92.
    static let overlay = AnyTransition.scale(scale: 0.92).combined(with: .opacity)

    /// Pi peek wings appearing/retracting beside the notch cutout. Opacity-led — the
    /// wings read as clip-growing because the black notch shape widens around them;
    /// children never scale on enter (clip, don't squash). The exit adds a slight
    /// shrink and runs ~25% faster (exits beat enters).
    static let peekWings = AnyTransition.asymmetric(
        insertion: .opacity.animation(peekWingEnter),
        removal: .scale(scale: 0.94).combined(with: .opacity).animation(peekWingExit)
    )

    /// Pi peek/activity text swap (thinking → forming → tool name → ✓): the incoming
    /// text drops in from −4pt while a 2pt blur resolves; the outgoing text falls +4pt
    /// and blurs away, ~25% faster. The blur bridges the two strings into one
    /// perceived object instead of a hard crossfade.
    static let textSwap = AnyTransition.asymmetric(
        insertion: .modifier(
            active: TextSwapEffect(offsetY: -4, blur: 2, opacity: 0),
            identity: TextSwapEffect(offsetY: 0, blur: 0, opacity: 1)
        ).animation(textSwapIn),
        removal: .modifier(
            active: TextSwapEffect(offsetY: 4, blur: 2, opacity: 0),
            identity: TextSwapEffect(offsetY: 0, blur: 0, opacity: 1)
        ).animation(textSwapOut)
    )

    /// Opacity-only transition for Reduce Motion: keeps the fade cue, drops movement.
    static let reducedTransition = AnyTransition.opacity

    /// Picks a movement transition or the opacity-only fallback.
    static func transition(_ full: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? reducedTransition : full
    }
}

/// Backs `Motion.textSwap`: translate + blur + fade as one unit so the swap reads as
/// a single object changing, not two strings trading places.
struct TextSwapEffect: ViewModifier {
    let offsetY: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: offsetY)
            .blur(radius: blur)
            .opacity(opacity)
    }
}
