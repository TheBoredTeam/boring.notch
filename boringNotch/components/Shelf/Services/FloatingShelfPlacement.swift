//
//  FloatingShelfPlacement.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import CoreGraphics

enum FloatingShelfPlacement {
    /// Square drop well, large enough for one shelf item and its name.
    static let panelSize = CGSize(width: 188, height: 188)
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
        shiftTriggerEnabled: Bool = true
    ) -> Bool {
        // The open notch already shows the shelf, so a second one is never stacked beside it.
        guard shelfEnabled, floatingShelfEnabled, !notchOpen, contentDragActive else { return false }
        return (shake && shakeTriggerEnabled) || (shiftHeld && shiftTriggerEnabled)
    }
}

enum FloatingShelfDismissPolicy {
    static func shouldClose(pointerInside: Bool) -> Bool {
        !pointerInside
    }
}
