//  NotchGeometry.swift
//  IslandNotch
//
//  Purpose: Detects whether the active display has a notch and computes the
//           top-center frame for the pill fallback on non-notch Macs.
//  Layer: Window

import AppKit

enum NotchGeometry {
    /// The screen we present the notch UI on (the built-in display if present).
    static var targetScreen: NSScreen? {
        // Prefer the screen that actually has a notch; else the main screen.
        NSScreen.screens.first(where: { hasNotch($0) }) ?? NSScreen.main
    }

    /// True when `screen` physically has a notch (non-zero top safe-area inset).
    static func hasNotch(_ screen: NSScreen) -> Bool {
        if #available(macOS 12.0, *) {
            return screen.safeAreaInsets.top > 0
        }
        return false
    }

    /// The notch's screen rect in AppKit (bottom-left origin) coordinates — i.e.
    /// the same space as `NSEvent.mouseLocation`. On non-notch Macs this falls back
    /// to a top-center band the height of the menu bar.
    static func notchRect(on screen: NSScreen) -> NSRect {
        let height = max(screen.safeAreaInsets.top, screen.frame.height - screen.visibleFrame.height)
        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        let notchWidth: CGFloat = {
            let computed = screen.frame.width - leftWidth - rightWidth
            return computed > 60 ? computed : 220 // fallback for non-notch / unknown
        }()
        return NSRect(
            x: screen.frame.midX - notchWidth / 2,
            y: screen.frame.maxY - height,
            width: notchWidth,
            height: height
        )
    }

    /// The drop catch zone for the AppKit `DropCatcher`. Deliberately small and
    /// hugging the notch — just the notch plus a modest margin, only as tall as the
    /// menu bar plus a thin strip below so it abuts the expanded shelf window. It is
    /// NOT the old 660×240 region: because the catcher only claims the cursor during
    /// a live file drag, keeping it small means even that case never overlaps real
    /// app content. Dragging *down* onto the expanded shelf is handled by the
    /// shelf's own SwiftUI `.onDrop`, so the catcher need not cover the shelf.
    static func dragApproachRect(on screen: NSScreen) -> NSRect {
        let notch = notchRect(on: screen)
        let horizontalMargin: CGFloat = 48
        let bottomOverlap: CGFloat = 44 // reach just below the menu bar to abut the shelf
        return NSRect(
            x: notch.minX - horizontalMargin,
            y: notch.minY - bottomOverlap,
            width: notch.width + horizontalMargin * 2,
            height: notch.height + bottomOverlap
        )
    }

    /// The hover target while the notch is CLOSED — the physical notch plus a small
    /// margin so it's easy to aim at. Hovering anywhere in here opens the notch
    /// (boring.notch behaviour). Kept tight so the rest of the menu bar stays usable.
    static func notchHoverRect(on screen: NSScreen) -> NSRect {
        let notch = notchRect(on: screen)
        return NSRect(
            x: notch.minX - 12,
            y: notch.minY - 6,
            width: notch.width + 24,
            height: notch.height + 6
        )
    }

    /// The hover target while the notch is OPEN — covers the expanded shelf so the
    /// notch stays open while the cursor is over its content, and collapses once the
    /// cursor leaves this region.
    static func expandedHoverRect(on screen: NSScreen) -> NSRect {
        let width: CGFloat = 700
        let height: CGFloat = 240
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// Approximate menu-bar height for positioning the pill below it.
    static func menuBarHeight(for screen: NSScreen) -> CGFloat {
        screen.frame.height - screen.visibleFrame.height
            - (screen.frame.maxY - screen.visibleFrame.maxY < 0 ? 0 : 0)
    }

    /// Frame for the top-center pill fallback (no-notch Macs), pinned just under
    /// the menu bar. `size` is the desired pill size.
    static func pillFrame(on screen: NSScreen, size: CGSize) -> NSRect {
        let x = screen.frame.midX - size.width / 2
        // visibleFrame.maxY sits just below the menu bar in AppKit's flipped-up
        // coordinate space, so anchor the pill's top there.
        let y = screen.visibleFrame.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
