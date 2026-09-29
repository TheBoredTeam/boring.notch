//
//  PointerShakeDetector.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import CoreGraphics
import Foundation

struct PointerSample: Equatable {
    var point: CGPoint
    var time: TimeInterval
}

/// Detects a locate-cursor style wiggle from pointer samples.
///
/// macOS enlarges the cursor when it sees this gesture, but that effect does not
/// run while the mouse button is held, and apps never receive an event for it.
/// A file drag is exactly that button-down case, so the shelf measures the wiggle itself.
struct PointerShakeDetector {
    /// Three direction changes is one short back-and-forth, not a curved drag.
    private let minimumReversals = 3
    /// Long enough for a flick of the wrist, short enough that a slow wander falls out of the window.
    private let window: TimeInterval = 0.45
    /// Ignore tracker jitter that is not an intentional stroke.
    private let minimumStep: CGFloat = 8
    private let cooldown: TimeInterval = 0.8

    private var samples: [PointerSample] = []
    private var lastTriggerTime: TimeInterval = -.greatestFiniteMagnitude

    mutating func reset() {
        samples.removeAll()
        lastTriggerTime = -.greatestFiniteMagnitude
    }

    /// Returns true once per shake. Further wiggles inside `cooldown` stay quiet.
    mutating func add(_ sample: PointerSample) -> Bool {
        samples.append(sample)
        let cutoff = sample.time - window
        samples.removeAll { $0.time < cutoff }
        if samples.count > 30 {
            samples.removeFirst(samples.count - 30)
        }

        guard sample.time - lastTriggerTime >= cooldown else { return false }
        guard reversalCount(in: samples) >= minimumReversals else { return false }

        lastTriggerTime = sample.time
        samples.removeAll()
        return true
    }

    private func reversalCount(in samples: [PointerSample]) -> Int {
        guard samples.count >= 3 else { return 0 }

        var reversals = 0
        var lastSignX = 0
        var lastSignY = 0

        for index in 1..<samples.count {
            let deltaX = samples[index].point.x - samples[index - 1].point.x
            let deltaY = samples[index].point.y - samples[index - 1].point.y
            guard hypot(deltaX, deltaY) >= minimumStep else { continue }

            if abs(deltaX) >= abs(deltaY) {
                reversals += Self.recordSign(of: deltaX, lastSign: &lastSignX)
            } else {
                reversals += Self.recordSign(of: deltaY, lastSign: &lastSignY)
            }
        }
        return reversals
    }

    private static func recordSign(of delta: CGFloat, lastSign: inout Int) -> Int {
        let sign = delta > 0 ? 1 : -1
        defer { lastSign = sign }
        guard lastSign != 0, sign != lastSign else { return 0 }
        return 1
    }
}
