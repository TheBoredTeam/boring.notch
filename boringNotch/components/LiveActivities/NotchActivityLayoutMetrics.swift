// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Foundation

/// Geometry shared by the activity host and its layout tests. The two side
/// allocations are intentionally equal: the app's window is centered on the
/// camera cutout, so unequal allocations would move the protected area away
/// from the hardware even when the total width looked correct.
struct NotchActivityLayoutMetrics: Equatable {
    let protectedWidth: CGFloat
    let sideWidth: CGFloat
    let height: CGFloat

    var width: CGFloat { protectedWidth + 2 * sideWidth }

    init(
        safeAreaWidth: CGFloat,
        height: CGFloat,
        maximumWidth: CGFloat,
        clearance: CGFloat = 8,
        leadingWidth: CGFloat,
        trailingWidth: CGFloat
    ) {
        let safeArea = Self.finiteNonnegative(safeAreaWidth)
        let desiredProtectedWidth = safeArea + 2 * Self.finiteNonnegative(clearance)
        protectedWidth = desiredProtectedWidth.isFinite ? desiredProtectedWidth : safeArea
        self.height = Self.finiteNonnegative(height)

        // A narrow proposal must never compress the physical safe area. When
        // it cannot fit, the side allocations collapse to zero instead.
        let sideBudget = max(0, (Self.finiteNonnegative(maximumWidth) - protectedWidth) / 2)
        let idealSideWidth = max(
            Self.finiteNonnegative(leadingWidth),
            Self.finiteNonnegative(trailingWidth)
        )
        sideWidth = min(idealSideWidth, sideBudget)
    }

    private static func finiteNonnegative(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 0
    }
}
