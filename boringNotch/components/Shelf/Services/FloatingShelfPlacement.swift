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

    /// Point in the panel nearest the pointer, in unit coordinates with y measured from the top
    /// (SwiftUI's convention), so the open animation grows out from the cursor.
    static func growthAnchor(cursor: CGPoint, frame: CGRect) -> CGPoint {
        let x = clamp((cursor.x - frame.minX) / frame.width, lower: 0, upper: 1)
        let y: CGFloat = frame.maxY <= cursor.y ? 0 : 1
        return CGPoint(x: x, y: y)
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
        shakeTriggerEnabled: Bool = true,
        shiftHeld: Bool,
        shiftTriggerEnabled: Bool = true,
        shortcutPressed: Bool
    ) -> Bool {
        // The open notch already shows the shelf, so a second one is never stacked beside it.
        guard shelfEnabled, floatingShelfEnabled, !notchOpen else { return false }
        if shortcutPressed { return true }
        guard contentDragActive else { return false }
        return (shake && shakeTriggerEnabled) || (shiftHeld && shiftTriggerEnabled)
    }
}

enum FloatingShelfDismissPolicy {
    /// A shortcut open with nothing being dragged stays up through hovers until the shelf is used.
    /// A drag-opened shelf, and a shortcut open during a drag, still close once the pointer has visited and left.
    static func shouldClose(
        hasVisited: Bool,
        pointerInside: Bool,
        sharingActive: Bool,
        grabbingItem: Bool,
        menuOpen: Bool,
        awaitsUse: Bool = false
    ) -> Bool {
        guard !awaitsUse else { return false }
        return hasVisited && !pointerInside && !sharingActive && !grabbingItem && !menuOpen
    }
}
