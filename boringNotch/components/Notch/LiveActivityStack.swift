// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Defaults
import SwiftUI

/// Browsing is an interaction on the selected slot, independent of providers and
/// arbitration. The host stays still while its individually clipped sides fade.
struct LiveActivityStack<Content: View>: View {
    let canCycle: Bool
    let onCycle: (LiveActivityCycleDirection) -> Bool
    @ViewBuilder let content: () -> Content
    @Default(.enableGestures) private var enableGestures
    @State private var haptics = false

    var body: some View {
        content()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 14)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height),
                              abs(value.translation.width) > 24 else { return }
                        cycle(value.translation.width < 0 ? .next : .previous)
                    },
                including: canCycle && enableGestures ? .all : .subviews
            )
            .accessibilityActions {
                if canCycle {
                    Button("Next activity") { cycle(.next) }
                    Button("Previous activity") { cycle(.previous) }
                }
            }
            .sensoryFeedback(.alignment, trigger: haptics)
    }

    private func cycle(_ direction: LiveActivityCycleDirection) {
        guard canCycle, onCycle(direction) else { return }
        if Defaults[.enableHaptics] { haptics.toggle() }
    }
}
