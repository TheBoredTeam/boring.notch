import CoreGraphics
import Foundation

func assertCondition(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("Assertion failed: \(message) — expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func assertRect(_ actual: CGRect, _ expected: CGRect, _ message: String) {
    let tolerance: CGFloat = 0.001
    let matches = abs(actual.origin.x - expected.origin.x) <= tolerance
        && abs(actual.origin.y - expected.origin.y) <= tolerance
        && abs(actual.size.width - expected.size.width) <= tolerance
        && abs(actual.size.height - expected.size.height) <= tolerance
    if !matches {
        fputs("Assertion failed: \(message) — expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func app(
    pid: pid_t,
    bundleID: String? = "com.example.app",
    policy: WindowTargetActivationPolicy = .regular,
    terminated: Bool = false
) -> WindowTargetApplicationSnapshot {
    WindowTargetApplicationSnapshot(
        pid: pid,
        bundleIdentifier: bundleID,
        activationPolicy: policy,
        isTerminated: terminated
    )
}


@main
struct WindowManagementRegressionRunner {
    static func main() {
        let ownPID: pid_t = 999
        let ownBundleID = "rohoswagger.gojo"
        let gojo = app(pid: ownPID, bundleID: ownBundleID, policy: .accessory)
        let safari = app(pid: 100, bundleID: "com.apple.Safari")
        let xcode = app(pid: 200, bundleID: "com.apple.dt.Xcode")
        let finder = app(pid: 300, bundleID: "com.apple.finder")

        assertEqual(
            WindowTargetResolver.resolve(
                frontmost: safari,
                lastTarget: xcode,
                topWindows: [],
                applicationsByPID: [safari.pid: safari, xcode.pid: xcode],
                ownPID: ownPID,
                ownBundleID: ownBundleID
            ),
            safari.pid,
            "a normal frontmost app should win"
        )

        assertEqual(
            WindowTargetResolver.resolve(
                frontmost: gojo,
                lastTarget: xcode,
                topWindows: [],
                applicationsByPID: [gojo.pid: gojo, xcode.pid: xcode],
                ownPID: ownPID,
                ownBundleID: ownBundleID
            ),
            xcode.pid,
            "when Gojo is frontmost, the last remembered normal app should remain controllable"
        )

        let topWindows = [
            WindowTargetWindowSnapshot(pid: ownPID, ownerName: "Gojo", layer: 0, bounds: CGRect(x: 0, y: 0, width: 1200, height: 160)),
            WindowTargetWindowSnapshot(pid: 60, ownerName: "Dock", layer: 0, bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
            WindowTargetWindowSnapshot(pid: finder.pid, ownerName: "Finder", layer: 0, bounds: CGRect(x: 24, y: 80, width: 900, height: 700))
        ]

        assertEqual(
            WindowTargetResolver.resolve(
                frontmost: gojo,
                lastTarget: nil,
                topWindows: topWindows,
                applicationsByPID: [gojo.pid: gojo, finder.pid: finder],
                ownPID: ownPID,
                ownBundleID: ownBundleID
            ),
            finder.pid,
            "when Gojo owns focus and there is no remembered app, the top normal CGWindow owner should be selected"
        )

        assertEqual(
            WindowTargetResolver.resolve(
                frontmost: WindowTargetApplicationSnapshot(
                    pid: 400,
                    bundleIdentifier: "rohoswagger.gojo",
                    activationPolicy: .accessory,
                    isTerminated: false
                ),
                lastTarget: nil,
                topWindows: topWindows,
                applicationsByPID: [gojo.pid: gojo, finder.pid: finder],
                ownPID: 401,
                excludedBundleIDs: ["rohoswagger.gojo", "rohoswagger.gojo.GojoXPCHelper"]
            ),
            finder.pid,
            "the XPC helper must exclude the host Gojo bundle, not just the helper's own PID"
        )

        let rect = CGRect(x: 12, y: 34, width: 640, height: 480)
        let cgInfo: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: Int32(safari.pid)),
            kCGWindowNumber as String: NSNumber(value: UInt32(42)),
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowOwnerName as String: "Safari",
            kCGWindowBounds as String: rect.dictionaryRepresentation
        ]
        let parsedWindow = WindowTargetWindowSnapshot(cgWindowInfo: cgInfo)
        assertCondition(parsedWindow != nil, "CGWindow dictionaries should parse NSNumber PID/layer values and dictionary bounds")
        assertEqual(parsedWindow?.windowID, 42, "parsed CGWindow window ID should match NSNumber-backed window number")
        assertEqual(parsedWindow?.pid, safari.pid, "parsed CGWindow PID should match NSNumber-backed PID")
        assertEqual(parsedWindow?.layer, 0, "parsed CGWindow layer should match NSNumber-backed layer")
        assertRect(parsedWindow?.bounds ?? .null, rect, "parsed CGWindow bounds should match dictionary bounds")

        assertCondition(
            !WindowTargetResolver.isTopLevelWindow(
                WindowTargetWindowSnapshot(pid: finder.pid, ownerName: "Control Center", layer: 0, bounds: rect),
                ownPID: ownPID
            ),
            "system overlay owners should be excluded from fallback targeting"
        )

        let primaryVisible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        assertRect(
            WindowFrameCalculator.targetFrame(for: .leftHalf, in: primaryVisible),
            CGRect(x: 0, y: 25, width: 720, height: 875),
            "left half should use the supplied display's visible bounds"
        )
        assertRect(
            WindowFrameCalculator.targetFrame(for: .topHalf, in: primaryVisible),
            CGRect(x: 0, y: 463, width: 1440, height: 437),
            "top half should pin to visibleFrame.maxY on the supplied display"
        )

        let externalVisible = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        assertRect(
            WindowFrameCalculator.targetFrame(for: .rightHalf, in: externalVisible),
            CGRect(x: -960, y: 0, width: 960, height: 1055),
            "right half on a left-side external display should stay within that display, not the main screen"
        )
        assertRect(
            WindowFrameCalculator.targetFrame(for: .bottomHalf, in: externalVisible),
            CGRect(x: -1920, y: 0, width: 1920, height: 527),
            "bottom half should stay within the supplied external display's visible bounds"
        )
        assertRect(
            WindowFrameCalculator.clampedRestoreFrame(
                CGRect(x: -2100, y: -40, width: 2600, height: 1300),
                in: externalVisible
            ),
            CGRect(x: -1920, y: 0, width: 1920, height: 1055),
            "restore should clamp oversized saved frames to the destination display"
        )

        assertEqual(
            WindowFrameCalculator.matchingAction(
                for: CGRect(x: -960, y: 0, width: 960, height: 1055),
                in: externalVisible
            ),
            .rightHalf,
            "active layout detection should classify right half relative to the external display"
        )

        assertEqual(
            WindowFrameCalculator.matchingAction(
                for: CGRect(x: 0, y: 463, width: 1440, height: 437),
                in: primaryVisible
            ),
            .topHalf,
            "active layout detection should classify top half relative to the focused window display"
        )

        print("window-management-regression-pass")
    }
}
