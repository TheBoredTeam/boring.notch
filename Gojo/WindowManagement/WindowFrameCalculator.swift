import CoreGraphics
import Foundation

enum WindowFrameCalculator {
    static func targetFrame(for action: WindowAction, in visibleFrame: CGRect) -> CGRect {
        let visibleFrame = visibleFrame.integral
        var frame = visibleFrame

        switch action {
        case .leftHalf:
            frame.size.width = floor(visibleFrame.width / 2)
            frame.origin.x = visibleFrame.minX
        case .rightHalf:
            frame.size.width = floor(visibleFrame.width / 2)
            frame.origin.x = visibleFrame.maxX - frame.width
        case .topHalf:
            frame.size.height = floor(visibleFrame.height / 2)
            frame.origin.y = visibleFrame.maxY - frame.height
        case .bottomHalf:
            frame.size.height = floor(visibleFrame.height / 2)
            frame.origin.y = visibleFrame.minY
        case .maximize:
            frame = visibleFrame
        case .zoom:
            // No fixed target frame — zoom is dispatched via the AX zoom button,
            // not by setting a frame. Caller should branch on .zoom before reaching here.
            break
        }

        return frame.integral
    }

    static func clampedRestoreFrame(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        let visibleFrame = visibleFrame.integral
        var restored = frame.integral

        restored.size.width = min(restored.width, visibleFrame.width)
        restored.size.height = min(restored.height, visibleFrame.height)

        if restored.minX < visibleFrame.minX {
            restored.origin.x = visibleFrame.minX
        }
        if restored.maxX > visibleFrame.maxX {
            restored.origin.x = visibleFrame.maxX - restored.width
        }
        if restored.minY < visibleFrame.minY {
            restored.origin.y = visibleFrame.minY
        }
        if restored.maxY > visibleFrame.maxY {
            restored.origin.y = visibleFrame.maxY - restored.height
        }

        return restored.integral
    }

    static func matchingAction(for frame: CGRect, in visibleFrame: CGRect, tolerance: CGFloat = 6) -> WindowAction? {
        let frame = frame.integral
        return WindowAction.allCases.first { action in
            guard action.isFrameBased else { return false }
            return matches(frame, targetFrame(for: action, in: visibleFrame), tolerance: tolerance)
        }
    }

    private static func matches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.size.width - rhs.size.width) <= tolerance
            && abs(lhs.size.height - rhs.size.height) <= tolerance
    }
}
