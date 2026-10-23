//
//  FloatingDropTargetPlacement.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import CoreGraphics

enum FloatingDropTargetPlacement {
    /// Square drop well, large enough for one shelf item and its name.
    static let panelSize = CGSize(width: 188, height: 188)
    static let screenMargin: CGFloat = 8
    static let visibleItemLimit = 3
    private static let shelfItemWidth: CGFloat = 115
    private static let shelfItemSpacing: CGFloat = 8
    /// Panel padding (12 per side) plus drop-well content padding (16 per side).
    private static let horizontalInsets: CGFloat = 56
    /// Gap so the target sits beside the pointer instead of chasing it during the rest of the shake.
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

    static func previewSize(itemCount: Int) -> CGSize {
        let visibleCount = min(max(itemCount, 1), visibleItemLimit)
        let itemsWidth = CGFloat(visibleCount) * shelfItemWidth
            + CGFloat(visibleCount - 1) * shelfItemSpacing
        return CGSize(
            width: max(panelSize.width, itemsWidth + horizontalInsets),
            height: panelSize.height
        )
    }

    static func previewFrame(currentFrame: CGRect, itemCount: Int, screenFrame: CGRect) -> CGRect {
        frame(matching: previewSize(itemCount: itemCount), currentFrame: currentFrame, screenFrame: screenFrame)
    }

    /// Keeps the panel's vertical edge and center while its animated width changes.
    static func frame(matching size: CGSize, currentFrame: CGRect, screenFrame: CGRect) -> CGRect {
        let preferredOrigin = CGPoint(
            x: currentFrame.midX - size.width / 2,
            y: currentFrame.minY
        )
        return CGRect(
            origin: clampedOrigin(preferredOrigin, panelSize: size, screenFrame: screenFrame),
            size: size
        )
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
