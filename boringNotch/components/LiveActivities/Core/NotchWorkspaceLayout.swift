// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// The host chooses the workspace bounds; a compact Home does not constrain
/// Shelf or a third-party tab to the music player's smaller content area.
struct NotchWorkspaceLayout {
    static let compactHomeWidth: CGFloat = 336
    let compactMode: Bool
    let selection: NotchViews
    let standardSize: CGSize
    let horizontalInset: CGFloat
    let topClearance: CGFloat

    var usesCompactHome: Bool { compactMode && selection == .home }
    var notchHeight: CGFloat? { usesCompactHome ? nil : standardSize.height }
    var contentWidth: CGFloat {
        usesCompactHome ? Self.compactHomeWidth : max(0, standardSize.width - 2 * horizontalInset)
    }
    var contentHeight: CGFloat? {
        usesCompactHome ? nil : max(0, standardSize.height - topClearance - 20)
    }
}

/// Shared by the inline strip, detached pill, and host window reservation.
enum NotchTabStripMetrics {
    static let buttonWidth: CGFloat = 44
    static let buttonHeight: CGFloat = 26
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 6
    static let floatingGap: CGFloat = 8
    static let floatingHeight = buttonHeight + 2 * verticalPadding
    static let floatingReservation = floatingGap + floatingHeight

    static func floatingContentWidth(tabCount: Int, maximumWidth: CGFloat) -> CGFloat {
        min(CGFloat(max(0, tabCount)) * buttonWidth, max(0, maximumWidth - 2 * horizontalPadding))
    }
}
