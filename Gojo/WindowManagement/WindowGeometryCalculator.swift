import AppKit

struct WindowGeometryCalculator {
    func targetFrame(for action: WindowAction, window: FocusedWindow) -> CGRect {
        WindowFrameCalculator.targetFrame(for: action, in: window.screen.visibleFrame)
    }

    func clampedRestoreFrame(_ frame: CGRect, for screen: NSScreen) -> CGRect {
        WindowFrameCalculator.clampedRestoreFrame(frame, in: screen.visibleFrame)
    }

    func matchingAction(for window: FocusedWindow) -> WindowAction? {
        WindowFrameCalculator.matchingAction(for: window.normalFrame, in: window.screen.visibleFrame)
    }
}
