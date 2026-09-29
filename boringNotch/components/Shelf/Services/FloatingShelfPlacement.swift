//
//  FloatingShelfPlacement.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import CoreGraphics

/// Where the floating shelf sits relative to the pointer, in AppKit coordinates (origin at the bottom left).
enum FloatingShelfPlacement {
    /// Wide enough for the share control on the left and the drop well beside it.
    static let panelSize = CGSize(width: 392, height: 168)
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

/// When a content drag is allowed to summon the floating shelf.
enum FloatingShelfTriggerPolicy {
    static func shouldPresent(
        shelfEnabled: Bool,
        floatingShelfEnabled: Bool,
        contentDragActive: Bool,
        shake: Bool,
        shiftHeld: Bool,
        shortcutPressed: Bool
    ) -> Bool {
        guard shelfEnabled, floatingShelfEnabled, contentDragActive else { return false }
        return shake || shiftHeld || shortcutPressed
    }
}
