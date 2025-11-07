//
//  LoftNotchWindow.swift
//  Zenith Loft (LoftOS)
//
//  Non-activating, transparent NSPanel tuned for a notch HUD.
//  - Lives above the menu bar (but below critical alerts)
//  - Non-key / non-main so it won't steal focus
//  - Optional click-through
//  - Joins all Spaces and rides along in fullscreen
//

import AppKit

public final class LoftNotchWindow: NSPanel {

    /// If true, the window ignores mouse events (perfect for passive HUDs).
    public var allowsHitThrough: Bool = false {
        didSet { ignoresMouseEvents = allowsHitThrough }
    }

    /// Designated initializer with sensible defaults for a notch HUD.
    public override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask = [.borderless],
        backing bufferingType: NSWindow.BackingStoreType = .buffered,
        defer flag: Bool = true
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)

        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        hasShadow = false

        // Ride along in fullscreen spaces, don't appear in app switcher, and don't cycle focus.
        collectionBehavior = [
            .fullScreenAuxiliary,
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle
        ]

        // Non-activating panel that sits above the menu bar but below screensaver/critical system alerts.
        // `statusBar` (or mainMenu+1..+3) works well; keep it conservative to avoid covering alerts.
        level = .statusBar

        // Do not release on close; we manage lifetime via controller.
        isReleasedWhenClosed = false

        // Start in click-through mode off (interactive). Toggle via `allowsHitThrough`.
        ignoresMouseEvents = allowsHitThrough

        // Improve compositing/smoothness for transparent corners.
        disablesScreenUpdatesUntilFlush = false
    }

    // Prevent focus stealing
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

// MARK: - Optional helpers

public extension LoftNotchWindow {
    /// Convenience to apply a rounded capsule mask to match a "pill" notch surface.
    func applyCapsuleMask(cornerRadius: CGFloat) {
        let maskView = NSView(frame: contentView?.bounds ?? .zero)
        maskView.wantsLayer = true
        let layer = CALayer()
        layer.backgroundColor = NSColor.white.cgColor
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true
        maskView.layer = layer
        contentView?.superview?.wantsLayer = true
        contentView?.superview?.layer?.mask = layer
        // Keep mask in sync with window resizes
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            guard let self, let superBounds = self.contentView?.superview?.bounds else { return }
            self.contentView?.superview?.layer?.mask?.frame = superBounds
        }
    }
}

// MARK: - Compatibility alias (so old code compiles while you migrate)
public typealias BoringNotchWindow = LoftNotchWindow
