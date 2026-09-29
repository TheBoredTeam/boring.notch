//
//  FloatingShelfPlacement.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import CoreGraphics

enum FloatingShelfPlacement {
    /// Slightly under the open notch (640×190). Insets match the open tray, so the shelf row stays about the same height.
    static let panelSize = CGSize(width: 544, height: 164)
    static let screenMargin: CGFloat = 8
    /// Gap so the shelf sits beside the pointer instead of chasing it during the rest of the shake.
    static let cursorGap: CGFloat = 12

    static func frame(cursor: CGPoint, screenFrame: CGRect, panelSize: CGSize = panelSize) -> CGRect {
        let belowPointer = cursor.y - panelSize.height - cursorGap
        let abovePointer = cursor.y + cursorGap
        let preferredY = belowPointer >= screenFrame.minY + screenMargin ? belowPointer : abovePointer
        let preferredX = cursor.x - panelSize.width / 2
        let origin = clampedOrigin(
            CGPoint(x: preferredX, y: preferredY),
            panelSize: panelSize,
            screenFrame: screenFrame
        )
        return CGRect(origin: origin, size: panelSize)
    }

    private static func clampedOrigin(_ origin: CGPoint, panelSize: CGSize, screenFrame: CGRect) -> CGPoint {
        let minX = screenFrame.minX + screenMargin
        let minY = screenFrame.minY + screenMargin
        let maxX = screenFrame.maxX - panelSize.width - screenMargin
        let maxY = screenFrame.maxY - panelSize.height - screenMargin
        return CGPoint(
            x: clamp(origin.x, lower: minX, upper: maxX),
            y: clamp(origin.y, lower: minY, upper: maxY)
        )
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper >= lower else { return lower }
        return min(max(value, lower), upper)
    }
}

enum FloatingShelfTriggerPolicy {
    static func shouldPresent(
        shelfEnabled: Bool,
        floatingShelfEnabled: Bool,
        notchOpen: Bool,
        contentDragActive: Bool,
        shake: Bool,
        shiftHeld: Bool,
        shortcutPressed: Bool
    ) -> Bool {
        // The open notch already shows the shelf, so a second one is never stacked beside it.
        guard shelfEnabled, floatingShelfEnabled, !notchOpen else { return false }
        if shortcutPressed { return true }
        guard contentDragActive else { return false }
        return shake || shiftHeld
    }
}

enum FloatingShelfDismissPolicy {
    /// A shortcut open has not been visited yet, so the pointer starting outside the panel must not close it.
    static func shouldClose(
        hasVisited: Bool,
        pointerInside: Bool,
        sharingActive: Bool,
        grabbingItem: Bool
    ) -> Bool {
        hasVisited && !pointerInside && !sharingActive && !grabbingItem
    }
}
