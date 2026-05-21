import AppKit
import ApplicationServices

struct FocusedWindow {
    let element: AXUIElement?
    let windowID: CGWindowID?
    let pid: pid_t
    let appName: String
    let bundleIdentifier: String?
    let title: String?
    let axFrame: CGRect
    let normalFrame: CGRect
    let screen: NSScreen

    var identity: String {
        if let windowID {
            return "window-\(windowID)"
        }
        let titlePart = title ?? "untitled"
        if let element {
            return "\(pid)-\(CFHash(element))-\(titlePart)"
        }
        return "\(pid)-\(normalFrame.integral.debugDescription)-\(titlePart)"
    }

    var displayTitle: String {
        if let title, !title.isEmpty {
            return "\(appName) · \(title)"
        }
        return appName
    }
}

extension CGRect {
    /// Converts between AX top-left-ish screen coordinates and AppKit bottom-left screen coordinates.
    /// Rectangle uses the same main-screen maxY flip before applying AX frames.
    var gojoScreenFlipped: CGRect {
        guard !isNull else { return self }
        let maxY = NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
        return CGRect(origin: CGPoint(x: origin.x, y: maxY - self.maxY), size: size)
    }

    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(size.width - other.size.width) <= tolerance
            && abs(size.height - other.size.height) <= tolerance
    }
}

extension NSScreen {
    static func screen(containing rect: CGRect) -> NSScreen? {
        let candidates = NSScreen.screens
        guard !candidates.isEmpty else { return NSScreen.main }

        return candidates.max { lhs, rhs in
            lhs.frame.intersection(rect).area < rhs.frame.intersection(rect).area
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
