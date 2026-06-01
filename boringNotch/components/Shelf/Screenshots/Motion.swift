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

    /// Opacity-only transition for Reduce Motion: keeps the fade cue, drops movement.
    static let reducedTransition = AnyTransition.opacity

    /// Picks a movement transition or the opacity-only fallback.
    static func transition(_ full: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? reducedTransition : full
    }
}
