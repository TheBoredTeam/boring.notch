import AppKit

final class OrbieWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 72, height: 72),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 120
            let y = screen.visibleFrame.maxY - 120
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func resize(to size: OrbieSize) {
        let dims = size.dimensions
        guard dims.width > 0, dims.height > 0 else { return }

        var frame = self.frame
        let dw = dims.width - frame.width
        let dh = dims.height - frame.height
        frame.size = dims
        frame.origin.x -= dw / 2
        frame.origin.y -= dh / 2

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.55
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            self.animator().setFrame(frame, display: true)
        }
    }
}
