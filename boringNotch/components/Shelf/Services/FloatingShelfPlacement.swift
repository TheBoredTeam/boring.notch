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

struct HeldModifiers: Equatable {
    var shift = false
    var control = false
    var option = false
    var command = false

    /// Hardware state. A drag owned by another app does not update `NSEvent.modifierFlags`.
    static func readHardware() -> HeldModifiers {
        let flags = CGEventSource.flagsState(.hidSystemState)
        return HeldModifiers(
            shift: flags.contains(.maskShift),
            control: flags.contains(.maskControl),
            option: flags.contains(.maskAlternate),
            command: flags.contains(.maskCommand)
        )
    }
}

enum FloatingShelfTriggerPolicy {
    static func shouldPresent(
        shelfEnabled: Bool,
        floatingShelfEnabled: Bool,
        contentDragActive: Bool,
        shake: Bool,
        shiftHeld: Bool,
        shortcutPressed: Bool
    ) -> Bool {
        guard shelfEnabled, floatingShelfEnabled else { return false }
        if shortcutPressed { return true }
        guard contentDragActive else { return false }
        return shake || shiftHeld
    }
}

enum FloatingShelfDismissPolicy {
    static func shouldClose(pointerInside: Bool, sharingActive: Bool) -> Bool {
        !pointerInside && !sharingActive
    }
}
