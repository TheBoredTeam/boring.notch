//
//  CodexAvatarView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

/// Presentation uses plain values so task observation remains with the containing view.
struct CodexStatusAvatarView: View {
    let style: CodexAvatarStyle
    let isActive: Bool
    let speedMultiplier: Double
    let phase: CodexActivityPhase
    let statusText: String

    var body: some View {
        Group {
            if style == .smile {
                AnimatedFace(height: 24, width: 30)
            } else {
                CodexAvatarView(style: style, isActive: isActive, speedMultiplier: speedMultiplier)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if phase == .waiting || phase == .error {
                Circle().fill(phase == .waiting ? Color.orange : .red)
                    .frame(width: 5, height: 5)
                    .overlay(Circle().stroke(.black, lineWidth: 1))
            }
        }
        .help(statusText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusText)
    }
}

/// Original geometric artwork. No OpenAI logo paths, images or animation assets are used.
struct CodexAvatarView: View {
    let style: CodexAvatarStyle
    let isActive: Bool
    var speedMultiplier: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CodexAvatarAnimation(style: style, isActive: isActive, reduceMotion: reduceMotion, speedMultiplier: speedMultiplier)
    }
}

struct CodexAvatarAnimation: View {
    let style: CodexAvatarStyle
    let isActive: Bool
    let reduceMotion: Bool
    var speedMultiplier: Double = 1
    @State private var rotation = CodexAvatarRotationClock()

    private var shouldAnimate: Bool { isActive && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !shouldAnimate)) { context in
            CodexActivityGlyph(style: style, turns: rotation.turns(at: context.date.timeIntervalSinceReferenceDate))
        }
        .frame(width: 30, height: 24)
        .onChange(of: shouldAnimate, initial: true) { _, _ in updateRotation() }
        .onChange(of: speedMultiplier) { _, _ in updateRotation() }
        .accessibilityHidden(true)
    }

    private func updateRotation() {
        rotation.update(isActive: shouldAnimate, speedMultiplier: speedMultiplier, at: Date().timeIntervalSinceReferenceDate)
    }
}

/// Integrates the old speed before changing it, so a new task never teleports the glyph.
struct CodexAvatarRotationClock {
    private var anchor: TimeInterval = 0
    private var anchorTurns: Double = 0
    private var turnsPerSecond: Double = 0

    func turns(at time: TimeInterval) -> Double {
        (anchorTurns + max(0, time - anchor) * turnsPerSecond).truncatingRemainder(dividingBy: 1)
    }

    mutating func update(isActive: Bool, speedMultiplier: Double, at time: TimeInterval) {
        anchorTurns = turns(at: time)
        anchor = time
        turnsPerSecond = isActive ? speedMultiplier / 6 : 0
    }
}

/// A deterministic frame also used by offscreen rendering tests.
struct CodexActivityGlyph: View {
    let style: CodexAvatarStyle
    var turns: Double = 0

    private var ink: AnyShapeStyle {
        if style == .colorfulOrbit {
            AnyShapeStyle(AngularGradient(colors: [.cyan, .mint, .yellow, .pink, .cyan], center: .center))
        } else {
            AnyShapeStyle(Color.white)
        }
    }

    var body: some View {
        Group {
            if style == .lines {
                HStack(spacing: 3) {
                    Capsule().frame(width: 2.4, height: 9)
                    Capsule().frame(width: 2.4, height: 17)
                    Capsule().frame(width: 2.4, height: 12)
                }
                .foregroundStyle(ink)
            } else {
                ZStack {
                    Circle().trim(from: 0.02, to: 0.37)
                        .stroke(ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    Circle().trim(from: 0.52, to: 0.87)
                        .stroke(ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    Circle().fill(ink).frame(width: 4, height: 4)
                }
                .frame(width: 18, height: 18)
            }
        }
        .frame(width: 30, height: 24)
        // Motion rotates the same ink at full opacity; idle never changes its brightness.
        .rotationEffect(.degrees(turns.truncatingRemainder(dividingBy: 1) * 360))
    }
}
