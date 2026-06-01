//  Motion.swift
//  IslandNotch
//
//  Purpose: One shared motion vocabulary so every notch animation feels like a
//           single system. The notch is a "Dynamic Island"-style surface, so its
//           layout uses springs (it should feel alive); content that enters/exits
//           uses strong ease-out curves (instant, responsive). Every duration
//           stays under ~250ms per UI-animation guidance, and exits are quicker
//           than entrances.
//  Layer: Support

import SwiftUI

enum Motion {
    // MARK: Springs (lively surfaces)

    /// Notch expand/collapse + layout reflow. Lively but barely bouncy.
    static let notch = Animation.spring(response: 0.34, dampingFraction: 0.80)

    // MARK: Window morph (DynamicNotchKit transitionConfiguration)
    //
    // These drive the actual NSPanel compact<->expanded morph AND the shelf's own
    // `isExpanded` reflow, so the window and its contents move as a single unit. The
    // notch is hovered open dozens of times a day, so the open is a snappy, almost
    // bounce-free spring under ~300ms; the close is quicker still (exits beat enters);
    // the conversion matches the open so a compact->expanded morph feels identical to
    // a fresh open now that the intermediate hide is skipped.

    /// Hidden/compact -> expanded. Snappy, low bounce — tuned for fast actuation so
    /// the surface reads as opening the instant the cursor commits.
    static let notchOpen = Animation.spring(response: 0.26, dampingFraction: 0.82)

    /// Expanded/compact -> hidden. Faster than the open.
    static let notchClose = Animation.spring(response: 0.24, dampingFraction: 0.90)

    /// compact <-> expanded conversion. Matches the open so the morph is cohesive.
    static let notchConvert = Animation.spring(response: 0.26, dampingFraction: 0.82)

    /// Reduced-motion window morph: near-instant, no spring overshoot. Movement is
    /// dropped while the cross-fade window alpha (handled by the package) still reads
    /// as a gentle fade.
    static let notchReduced = Animation.easeOut(duration: 0.10)

    /// A thumbnail settling into / leaving the shelf — a touch more bounce so a
    /// new capture feels like it "drops" in.
    static let shelfItem = Animation.spring(response: 0.30, dampingFraction: 0.72)

    // MARK: Ease-out curves (overlays, feedback)

    /// Strong ease-out (quint). For overlays appearing: feels immediate.
    static let easeOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)

    /// Snappy press feedback / fast exits — the system responding right now.
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.13)

    /// Gentle hover affordances.
    static let hover = Animation.easeOut(duration: 0.16)

    /// Delay before opening when the cursor reaches the notch. Kept tiny so actuation
    /// feels immediate; just enough to reject a cursor merely passing through the notch.
    static let hoverOpenDelay: Duration = .milliseconds(55)

    /// Delay before collapsing when idle after a drop or drag leaves the zone.
    static let collapseDelay: Duration = .milliseconds(250)

    // MARK: Transitions

    /// Shelf thumbnail enter/leave. Scale *up from* 0.9 (never from 0 — nothing in
    /// the real world appears from nothing) plus a fade. Removal is a hair smaller
    /// and rides the faster curve.
    static let thumbnail = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.9).combined(with: .opacity),
        removal: .scale(scale: 0.94).combined(with: .opacity)
    )

    /// Overlays anchored to the shelf (drop zone, copied flash): scale from 0.96.
    static let overlay = AnyTransition.scale(scale: 0.96).combined(with: .opacity)

    // MARK: Reduced motion

    /// Opacity-only transition for users who prefer reduced motion: keeps the
    /// comprehension cue (fade) but drops all movement/scale.
    static let reducedTransition = AnyTransition.opacity

    /// Picks a movement transition or the opacity-only fallback.
    static func transition(_ full: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? reducedTransition : full
    }
}
