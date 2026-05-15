import AppKit

final class NoteWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 720),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 400
            let y = screen.visibleFrame.minY + 20
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    override var canBecomeKey: Bool { true }
}
