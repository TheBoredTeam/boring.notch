//
//  LowBatteryState.swift
//  boringNotch
//

import Foundation

/// Decides *when* a low-battery warning should fire.
///
/// Kept free of IOKit and of any UI so the hysteresis rules can be unit tested directly.
/// The whole point is that the warning fires once when the battery crosses into the
/// low-battery range, not on every level update while it stays there.
struct LowBatteryState: Equatable {
    /// How far the battery must climb back above the threshold before the warning is
    /// allowed to fire again. Without this, a battery hovering on the boundary would
    /// re-arm and re-fire repeatedly.
    static let rearmMargin: Int = 5

    /// True once a warning has fired for the current discharge cycle.
    private(set) var hasWarned: Bool = false

    /// The threshold the current armed state was evaluated against, so that changing the
    /// setting re-arms rather than silently keeping a stale decision.
    private(set) var evaluatedThreshold: Int?

    struct Input: Equatable {
        var hasBattery: Bool
        var isPluggedIn: Bool
        /// Charge percentage, 0...100.
        var level: Int
        var threshold: Int
        var enabled: Bool
    }

    /// Feed the latest battery reading in and find out whether to show the warning now.
    ///
    /// - Returns: `true` exactly on the update that crosses into the low-battery range.
    mutating func update(_ input: Input) -> Bool {
        // A Mac with no battery never warns, and neither does a disabled feature. Reset
        // so that re-enabling the setting behaves like a fresh start.
        guard input.enabled, input.hasBattery else {
            hasWarned = false
            evaluatedThreshold = nil
            return false
        }

        // Changing the threshold invalidates the previous decision.
        if evaluatedThreshold != input.threshold {
            evaluatedThreshold = input.threshold
            hasWarned = false
        }

        // On AC power there is nothing to warn about, and reconnecting the charger is the
        // clearest signal that the discharge cycle is over.
        if input.isPluggedIn {
            hasWarned = false
            return false
        }

        // Re-arm once the battery has recovered clearly above the threshold.
        if input.level > input.threshold + Self.rearmMargin {
            hasWarned = false
            return false
        }

        guard input.level <= input.threshold, !hasWarned else { return false }

        hasWarned = true
        return true
    }

    /// Whether a warning is currently outstanding for this discharge cycle.
    var isWarningActive: Bool { hasWarned }
}
