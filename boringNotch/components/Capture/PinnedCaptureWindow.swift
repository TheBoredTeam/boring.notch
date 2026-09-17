//
//  PinnedCaptureWindow.swift
//  boringNotch
//
//  Floats a capture above everything as a reference card.
//
//  The use case is comparing two things that can't be on screen together —
//  a design against an implementation, a figure against a table. So it stays
//  on top across spaces, can be dragged anywhere, and closes on a click.
//

import AppKit
import CoreGraphics

final class PinnedCaptureWindow: NSPanel {
    private static var open: [PinnedCaptureWindow] = []

    /// Longest side a pinned card is allowed to be.
    ///
    /// A full-screen capture pinned at native size would cover the screen it
    /// is meant to be compared against, so it is scaled down to something
    /// that reads as a card.
    private static let maximumSide: CGFloat = 480

    static func present(image: CGImage) {
        let window = PinnedCaptureWindow(image: image)
        window.center()
        // Offset each new card so a run of pins doesn't hide behind itself.
        if let last = open.last {
            window.setFrameOrigin(CGPoint(x: last.frame.minX + 24, y: last.frame.minY - 24))
        }
        window.orderFrontRegardless()
        open.append(window)
    }

    private init(image: CGImage) {
        let size = Self.displaySize(for: image)
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Dragging by the image itself, since a borderless card has no title
        // bar to grab.
        isMovableByWindowBackground = true

        let imageView = ClickThroughImageView(frame: CGRect(origin: .zero, size: size))
        imageView.image = NSImage(cgImage: image, size: size)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        imageView.onClose = { [weak self] in self?.dismiss() }

        contentView = imageView
    }

    private func dismiss() {
        orderOut(nil)
        Self.open.removeAll { $0 === self }
    }

    private static func displaySize(for image: CGImage) -> CGSize {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0 else { return CGSize(width: 200, height: 200) }

        let scale = min(1, maximumSide / max(width, height))
        return CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
    }
}

/// An image view that closes its window on a double-click.
///
/// Double rather than single: the card is dragged by its background, and a
/// single-click close would fire at the end of every drag.
private final class ClickThroughImageView: NSImageView {
    var onClose: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onClose?()
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
