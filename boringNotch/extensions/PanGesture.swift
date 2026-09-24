//
//  PanGesture.swift
//  boringNotch
//
//  Created by Richard Kunkli on 21/08/2024.
//

import AppKit
import SwiftUI
import Combine
import Defaults

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

extension View {
    func panGesture(direction: PanDirection, threshold: CGFloat = 4, action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        self
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let s = direction.signed(from: value.translation)
                        guard s > 0, s.magnitude >= threshold else { return }
                        action(s.magnitude, .changed)
                    }
                    .onEnded { _ in action(0, .ended) }
            )
            .background(ScrollMonitor(direction: direction, threshold: threshold, action: action))
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }

    func makeCoordinator() -> Coordinator {
        Coordinator(direction: direction, threshold: threshold, action: action)
    }

    @MainActor final class Coordinator: NSObject {
        private let direction: PanDirection
        private let threshold: CGFloat
        private let action: (CGFloat, NSEvent.Phase) -> Void
        private var localMonitor: Any?
        private var accumulated: CGFloat = 0
        private var active = false
        private var endTask: Task<Void, Never>?
        private var endDeadline: ContinuousClock.Instant?
        private var normalizeDirection = Defaults[.normalizeGestureDirection]
        private var defaultsObserver: AnyCancellable?
        private let noiseThreshold: CGFloat = 0.2

        init(direction: PanDirection, threshold: CGFloat, action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            self.direction = direction
            self.threshold = threshold
            self.action = action
        }

        private func cancelEndTimeout() {
            endTask?.cancel()
            endTask = nil
            endDeadline = nil
        }

        private func scheduleEndTimeout() {
            // Refresh the deadline; a single task re-checks it instead of one task per event.
            endDeadline = .now + .milliseconds(300)
            guard endTask == nil else { return }
            endTask = Task { @MainActor in
                // If no new scroll event arrives within this window, consider the gesture ended.
                while let deadline = endDeadline, deadline > .now {
                    try? await Task.sleep(until: deadline, clock: .continuous)
                    guard !Task.isCancelled else { return }
                }
                endTask = nil
                endDeadline = nil
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
            }
        }

        func installMonitor(on view: NSView) {
            removeMonitor()

            normalizeDirection = Defaults[.normalizeGestureDirection]
            defaultsObserver = Defaults.publisher(.normalizeGestureDirection)
                .sink { change in
                    let newValue = change.newValue
                    Task { @MainActor [weak self] in self?.normalizeDirection = newValue }
                }

            // Local monitor for normal in-window scroll events.
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self = self, event.window === view?.window else { return event }
                self.handleScroll(event)
                return event
            }
        }

        func removeMonitor() {
            if let lm = localMonitor {
                NSEvent.removeMonitor(lm)
                self.localMonitor = nil
            }

            defaultsObserver = nil
            accumulated = 0
            active = false
            cancelEndTimeout()
        }

        private func handleScroll(_ event: NSEvent) {
            if event.phase == .ended || event.momentumPhase == .ended {
                // Explicit end wins; drop the pending timeout so `.ended` fires once.
                cancelEndTimeout()
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
                return
            }

            // Only consider scroll events that are primarily along the configured axis.
            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            // Require the movement along the gesture axis to be at least 1.5x the orthogonal axis.
            let axisDominanceFactor: CGFloat = 1.5
            let isAxisDominant: Bool = direction.isHorizontal ? (absDX >= axisDominanceFactor * absDY) : (absDY >= axisDominanceFactor * absDX)
            guard isAxisDominant else { return }

            // Determine whether to normalize system deltas to device (physical) direction.
            let deviceDirectionMultiplier: CGFloat = normalizeDirection ? (event.isDirectionInvertedFromDevice ? 1 : -1) : 1

            // Scale non-precise (mouse wheel) scrolling deltas so they feel similar to
            // trackpad gestures.
            let rawDelta = direction.signed(
                deltaX: event.scrollingDeltaX * deviceDirectionMultiplier,
                deltaY: event.scrollingDeltaY * deviceDirectionMultiplier
            )
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            let delta = rawDelta * scale

            guard delta.magnitude > noiseThreshold else {
                scheduleEndTimeout()
                return
            }

            if delta > 0 {
                accumulated += delta
            } else {
                accumulated = 0
            }

            if !active && accumulated >= threshold {
                active = true
                action(accumulated, .began)
            } else if active {
                action(accumulated, .changed)
            }
            // Schedule a timeout to end the gesture if no further scroll events arrive.
            scheduleEndTimeout()
        }
    }
}
