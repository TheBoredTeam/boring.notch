//
//  DraggableProgressBarView.swift
//  boringNotch
//
//  Created by Alexander on 2026-02-07.
//

import SwiftUI
import Defaults

public struct DraggableProgressBar: View {
    /// Floating point round trips through the system APIs, so full is a neighbourhood
    /// rather than exactly 1.
    private static let limitEpsilon: CGFloat = 0.001
    /// How long the bar stays compressed before it starts springing back.
    private static let impactDuration: TimeInterval = 0.09
    /// Impact plus rebound, used to rate-limit repeats.
    private static let recoilDuration: TimeInterval = 0.43

    @Binding public var value: CGFloat
    public var onChange: ((CGFloat) -> Void)? = nil
    public var accentColor: Color? = nil
    public var compact: Bool = false
    /// Monotonically increasing count of OSD show events, from `sneakPeek.eventCount`.
    /// Watching it is what lets the bar react to a key press that cannot move the value.
    public var eventCount: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDragging = false
    @State private var isRecoiling = false
    @State private var lastRecoilAt: Date = .distantPast

    public init(value: Binding<CGFloat>, onChange: ((CGFloat) -> Void)? = nil, accentColor: Color? = nil, compact: Bool = false, eventCount: Int = 0) {
        self._value = value
        self.onChange = onChange
        self.accentColor = accentColor
        self.compact = compact
        self.eventCount = eventCount
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.tertiary)
                Capsule()
                    .fill(fillStyle())
                    .frame(width: max(0, min(geo.size.width * value, geo.size.width)))
                    .shadow(color: shadowColor(), radius: 8, x: 3)
                    .opacity(value.isZero ? 0 : 1)
                    // Reads as the fill lighting up on impact, and is the whole of the
                    // effect when the user has asked for reduced motion.
                    .brightness(isRecoiling ? 0.22 : 0)
            }
            // Squash against the wall it just hit, then spring back. Anchoring at the
            // trailing edge is what makes it read as an impact rather than a pulse.
            .scaleEffect(
                x: (isRecoiling && !reduceMotion) ? 0.94 : 1,
                y: (isRecoiling && !reduceMotion) ? 1.25 : 1,
                anchor: .trailing
            )
            .contentShape(Rectangle())
            .gesture(dragGesture(in: geo))
            .onChange(of: eventCount) {
                // A fresh event while already full means the user pushed past the ceiling.
                if isAtLimit(value) { playLimitRecoil() }
            }
            .onAppear {
                // The OSD is torn down between showings, so the press that summons it back
                // arrives before this view exists and `onChange` never sees it.
                if isAtLimit(value) { playLimitRecoil() }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(NSLocalizedString("OSD.ValueLabel", comment: "Label for OSD value slider")))
            .accessibilityValue(
                Text(value, format: .percent.precision(.fractionLength(0)))
            )
            .accessibilityAdjustableAction { direction in
                let step: CGFloat = 0.05
                switch direction {
                case .increment:
                    updateValueClamped(value + step)
                case .decrement:
                    updateValueClamped(value - step)
                default: break
                }
            }
        }
        .frame(height: compact ? (Defaults[.inlineOSD] ? 6 : 7) : (Defaults[.inlineOSD] ? (isDragging ? 8 : 5) : (isDragging ? 9 : 6)))
    }

    private func fillStyle() -> AnyShapeStyle {
        if let c = accentColor {
            if Defaults[.enableGradient] {
                return AnyShapeStyle(LinearGradient(
                    colors: [c, c.ensureMinimumBrightness(factor: 0.2)],
                    startPoint: .trailing,
                    endPoint: .leading
                ))
            } else {
                return AnyShapeStyle(c)
            }
        }

        if Defaults[.enableGradient] {
            return AnyShapeStyle(LinearGradient(
                colors: Defaults[.systemEventIndicatorUseAccent] ?
                [Color.effectiveAccent, Color.effectiveAccent.ensureMinimumBrightness(factor: 0.2)] :
                [Color.white, Color.white.opacity(0.2)],
                startPoint: .trailing,
                endPoint: .leading
            ))
        }

        return AnyShapeStyle(Defaults[.systemEventIndicatorUseAccent] ? Color.effectiveAccent : Color.white)
    }

    private func shadowColor() -> Color {
        guard Defaults[.systemEventIndicatorShadow] else { return .clear }
        if let c = accentColor { return c.ensureMinimumBrightness(factor: 0.7) }
        return Defaults[.systemEventIndicatorUseAccent] ? Color.effectiveAccent.ensureMinimumBrightness(factor: 0.7) : Color.white
    }

    private func dragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                withAnimation(.smooth(duration: 0.12)) {
                    isDragging = true
                    updateValue(from: gesture.location.x, in: geo.size.width)
                }
            }
            .onEnded { _ in
                withAnimation(.smooth(duration: 0.12)) {
                    isDragging = false
                }
            }
    }

    private func updateValue(from x: CGFloat, in width: CGFloat) {
        guard width > 0 else { return }
        let newValue = x / width
        updateValueClamped(newValue)
    }

    private func updateValueClamped(_ newValue: CGFloat) {
        let clamped = max(0, min(newValue, 1))
        if clamped != value {
            let wasAtLimit = isAtLimit(value)
            value = clamped
            onChange?(value)
            // Dragging does not raise an OSD event, so the drag has to say so itself.
            if !wasAtLimit, isAtLimit(clamped) { playLimitRecoil() }
        }
    }

    private func isAtLimit(_ value: CGFloat) -> Bool {
        value >= 1 - Self.limitEpsilon
    }

    /// Squash the bar against its trailing edge and let it spring back, so reaching the
    /// maximum feels like hitting a wall rather than just stopping.
    private func playLimitRecoil() {
        guard Defaults[.osdLimitBounce] else { return }

        // A held key repeats faster than this animation runs. Letting one impact finish
        // before starting the next keeps it from stuttering into a sustained squash.
        let now = Date()
        guard now.timeIntervalSince(lastRecoilAt) > Self.recoilDuration else { return }
        lastRecoilAt = now

        withAnimation(.easeOut(duration: Self.impactDuration)) { isRecoiling = true }
        // Two separate runloop turns: collapsing them into one would let SwiftUI coalesce
        // the pair into a single update and never render the squash at all.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.impactDuration))
            // Deliberately under-damped — the overshoot is what sells the rebound.
            withAnimation(.spring(response: 0.34, dampingFraction: 0.42)) { isRecoiling = false }
        }
    }
}
