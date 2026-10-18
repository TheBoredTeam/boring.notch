// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Foundation

/// Compact is a bounded presentation shared by every tab. Selecting content
/// never changes the host's size; providers adapt their own controls to it.
struct NotchWorkspaceLayout {
    static let compactContentWidth: CGFloat = 336
    static let compactContentHeight: CGFloat = 132
    let compactMode: Bool
    let standardSize: CGSize
    let horizontalInset: CGFloat
    let topClearance: CGFloat

    var notchHeight: CGFloat {
        compactMode ? min(standardSize.height, topClearance + 20 + contentHeight) : standardSize.height
    }
    var contentWidth: CGFloat {
        let available = max(0, standardSize.width - 2 * horizontalInset)
        return compactMode ? min(Self.compactContentWidth, available) : available
    }
    var contentHeight: CGFloat {
        let available = max(0, standardSize.height - topClearance - 20)
        return compactMode ? min(Self.compactContentHeight, available) : available
    }
}

/// Placement does not change visibility preferences. Compact keeps Shelf
/// available, while both standard placements honor “Always show tabs”.
enum NotchTabVisibility {
    static func shouldShow(compactMode: Bool, shelfEnabled: Bool, shelfIsEmpty: Bool,
                           alwaysShowTabs: Bool, hasExtensionTabs: Bool) -> Bool {
        hasExtensionTabs || (shelfEnabled && (compactMode || !shelfIsEmpty || alwaysShowTabs))
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
