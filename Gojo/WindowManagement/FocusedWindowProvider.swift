import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

@MainActor
final class FocusedWindowProvider {
    enum ProviderError: Error {
        case permissionMissing
        case noFocusedWindow
        case noFocusedWindowOnScreen
        case missingFrame
        case unsupportedWindow
    }

    private var activationObserver: Any?
    private var lastTargetApplication: NSRunningApplication?
    private let ownBundleID = Bundle.main.bundleIdentifier

    init() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor in
                self?.rememberTargetApplicationIfNeeded(app)
            }
        }

        if let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            rememberTargetApplicationIfNeeded(frontmostApplication)
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    /// Resolves the window to tile for a notch on `notchScreen`, preferring focus on that display.
    func focusedWindow(for notchScreen: NSScreen?, promptIfNeeded: Bool = false) async throws -> FocusedWindow {
        guard let notchScreen else {
            return try await focusedWindow(promptIfNeeded: promptIfNeeded)
        }

        let global = try await focusedWindow(promptIfNeeded: promptIfNeeded)
        if global.screen.displayUUID == notchScreen.displayUUID {
            gojoDebug("resolve: global focus \(global.appName) on \(notchScreen.localizedName)")
            return global
        }

        if let onScreen = try await focusedWindowOnNotchScreen(notchScreen, promptIfNeeded: promptIfNeeded) {
            gojoDebug("resolve: global \(global.appName) on \(global.screen.localizedName) ≠ notch \(notchScreen.localizedName) → top window \(onScreen.appName)")
            return onScreen
        }

        gojoDebug("resolve: no window on \(notchScreen.localizedName) (global \(global.appName) on \(global.screen.localizedName)) → noFocusedWindowOnScreen")
        throw ProviderError.noFocusedWindowOnScreen
    }

    func focusedWindow(promptIfNeeded: Bool = false) async throws -> FocusedWindow {
        let authorized = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: promptIfNeeded)
        guard authorized else { throw ProviderError.permissionMissing }

        // Resolve the target here, in the main app — NOT via the helper's
        // focusedWindowSnapshot. The helper is an XPC service whose NSWorkspace
        // frontmost-app state goes stale (no real app lifecycle), so it kept
        // returning whichever app was frontmost around helper launch. Live
        // workspace state lives in this process; the helper is only used for
        // AX writes addressed by pid+windowID.
        guard let app = targetApplication() else {
            throw ProviderError.noFocusedWindow
        }

        rememberTargetApplicationIfNeeded(app)

        // Main process holds no AX permission, so build the window from
        // CGWindowList: the frontmost app's topmost on-screen window is its
        // focused window for tiling purposes.
        if let snapshot = topWindowSnapshots().first(where: { $0.pid == app.processIdentifier }),
           !snapshot.bounds.isNull, snapshot.bounds.width > 0, snapshot.bounds.height > 0 {
            let normalFrame = snapshot.bounds.gojoScreenFlipped
            if let screen = NSScreen.screen(containing: normalFrame) ?? NSScreen.main ?? NSScreen.screens.first {
                gojoDebug("resolve: live frontmost \(app.localizedName ?? "?") pid=\(app.processIdentifier) windowID=\(String(describing: snapshot.windowID)) on \(screen.localizedName)")
                return FocusedWindow(
                    element: nil,
                    windowID: snapshot.windowID,
                    pid: app.processIdentifier,
                    appName: app.localizedName ?? "Focused app",
                    bundleIdentifier: app.bundleIdentifier,
                    title: nil,
                    axFrame: snapshot.bounds,
                    normalFrame: normalFrame,
                    screen: screen
                )
            }
        }

        // Last-ditch AX fallback (only effective if the main app is ever
        // granted Accessibility directly).
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let preferredWindowID = preferredTopWindowID(for: app.processIdentifier)
        let windowElement = bestWindowElement(for: appElement, preferredWindowID: preferredWindowID)
        guard let windowElement else { throw ProviderError.noFocusedWindow }

        if let role = copyString(windowElement, attribute: kAXRoleAttribute), role != kAXWindowRole as String {
            throw ProviderError.unsupportedWindow
        }

        guard let axFrame = frame(of: windowElement), !axFrame.isNull, axFrame.width > 0, axFrame.height > 0 else {
            throw ProviderError.missingFrame
        }

        let normalFrame = axFrame.gojoScreenFlipped
        let screen = NSScreen.screen(containing: normalFrame) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { throw ProviderError.missingFrame }

        return FocusedWindow(
            element: windowElement,
            windowID: windowID(of: windowElement),
            pid: app.processIdentifier,
            appName: app.localizedName ?? "Focused app",
            bundleIdentifier: app.bundleIdentifier,
            title: copyString(windowElement, attribute: kAXTitleAttribute),
            axFrame: axFrame,
            normalFrame: normalFrame,
            screen: screen
        )
    }

    /// Returns user-facing windows on `screen` in current-Space z-order. Filters to regular activation policy
    /// apps with usable window sizes — excludes floating panels, menu bar helpers, and accessory utilities.
    func enumerateWindows(on screen: NSScreen) -> [WindowSummary] {
        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let targetUUID = screen.displayUUID
        let visibleFrame = screen.visibleFrame
        let minWidth: CGFloat = 200
        let minHeight: CGFloat = 120

        let snapshots = topWindowSnapshots().filter { snapshot in
            guard WindowTargetResolver.isTopLevelWindow(snapshot, ownPID: ownPID) else { return false }
            guard snapshot.bounds.width >= minWidth, snapshot.bounds.height >= minHeight else { return false }
            let normalFrame = snapshot.bounds.gojoScreenFlipped
            guard let windowScreen = NSScreen.screen(containing: normalFrame),
                  windowScreen.displayUUID == targetUUID else { return false }
            return true
        }

        var seenIDs = Set<String>()
        return snapshots.compactMap { snapshot -> WindowSummary? in
            guard let app = NSRunningApplication(processIdentifier: snapshot.pid),
                  app.activationPolicy == .regular,
                  isTargetApplication(app) else { return nil }

            let normalFrame = snapshot.bounds.gojoScreenFlipped
            let action = WindowFrameCalculator.matchingAction(for: normalFrame, in: visibleFrame)
            let id = snapshot.windowID.map { "win-\($0)" } ?? "pid-\(snapshot.pid)-\(Int(snapshot.bounds.origin.x))-\(Int(snapshot.bounds.origin.y))"
            guard seenIDs.insert(id).inserted else { return nil }

            return WindowSummary(
                id: id,
                pid: snapshot.pid,
                windowID: snapshot.windowID,
                appName: app.localizedName ?? snapshot.ownerName ?? "App",
                bundleIdentifier: app.bundleIdentifier,
                icon: app.icon,
                title: nil,
                normalFrame: normalFrame,
                currentAction: action
            )
        }
    }

    /// Raises a specific window owned by `pid` to the front via Accessibility — required for cross-app
    /// window activation from a non-activating panel like the notch.
    func raiseWindow(pid: pid_t, windowID: CGWindowID?) {
        let appElement = AXUIElementCreateApplication(pid)
        var targetElement: AXUIElement?

        if let windowID,
           let windows = copyElements(appElement, attribute: kAXWindowsAttribute) {
            for window in windows {
                if self.windowID(of: window) == windowID {
                    targetElement = window
                    break
                }
            }
        }

        if targetElement == nil {
            targetElement = bestWindowElement(for: appElement, preferredWindowID: windowID)
        }

        if let element = targetElement {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    /// Resolves a `FocusedWindow` for a specific pid+windowID without depending on system focus state.
    /// Returns nil if AX cannot find the window.
    func resolveWindow(pid: pid_t, windowID: CGWindowID?, fallbackAppName: String, fallbackTitle: String? = nil) -> FocusedWindow? {
        let appElement = AXUIElementCreateApplication(pid)
        guard let windowElement = bestWindowElement(for: appElement, preferredWindowID: windowID),
              isUsableWindow(windowElement) else {
            return nil
        }
        guard let axFrame = frame(of: windowElement), !axFrame.isNull, axFrame.width > 0, axFrame.height > 0 else {
            return nil
        }

        let normalFrame = axFrame.gojoScreenFlipped
        guard let screen = NSScreen.screen(containing: normalFrame) ?? NSScreen.main else {
            return nil
        }

        let app = NSRunningApplication(processIdentifier: pid)
        return FocusedWindow(
            element: windowElement,
            windowID: self.windowID(of: windowElement) ?? windowID,
            pid: pid,
            appName: app?.localizedName ?? fallbackAppName,
            bundleIdentifier: app?.bundleIdentifier,
            title: copyString(windowElement, attribute: kAXTitleAttribute) ?? fallbackTitle,
            axFrame: axFrame,
            normalFrame: normalFrame,
            screen: screen
        )
    }

    func setFrame(_ normalFrame: CGRect, for window: FocusedWindow) async -> Bool {
        guard let element = window.element else {
            // Address the window by pid+windowID rather than letting the helper
            // re-resolve "the focused window" — for fallback targets (top window
            // on the notch's display) the frontmost app is a different window.
            let ok = await XPCHelperClient.shared.setWindowFrame(normalFrame, pid: window.pid, windowID: window.windowID)
            gojoDebug("setFrame[helper] \(window.appName) windowID=\(String(describing: window.windowID)) → \(ok ? "ok" : "FAILED") frame=\(normalFrame)")
            return ok
        }

        let axFrame = normalFrame.gojoScreenFlipped
        let ok = setAXFrame(axFrame, for: element, pid: window.pid)
        gojoDebug("setFrame[direct] \(window.appName) → \(ok ? "ok" : "FAILED") axFrame=\(axFrame)")
        return ok
    }

    private func focusedWindowOnNotchScreen(_ screen: NSScreen, promptIfNeeded: Bool) async throws -> FocusedWindow? {
        let authorized = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: promptIfNeeded)
        guard authorized else { throw ProviderError.permissionMissing }

        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let targetUUID = screen.displayUUID

        let candidates = topWindowSnapshots().filter { snapshot in
            guard WindowTargetResolver.isTopLevelWindow(snapshot, ownPID: ownPID) else { return false }
            guard let windowScreen = NSScreen.screen(containing: snapshot.bounds.gojoScreenFlipped),
                  windowScreen.displayUUID == targetUUID else { return false }
            return true
        }

        guard let snapshot = candidates.first,
              let app = NSRunningApplication(processIdentifier: snapshot.pid),
              isTargetApplication(app) else {
            if let first = candidates.first {
                gojoDebug("resolve: top candidate on \(screen.localizedName) rejected (pid=\(first.pid) \(first.ownerName ?? "?"))")
            }
            return nil
        }

        rememberTargetApplicationIfNeeded(app)

        // Build the FocusedWindow purely from the CG snapshot — no AX reads.
        // Only the XPC helper holds Accessibility permission; AX lookups from
        // this (main) process always fail, which used to make this fallback a
        // dead path for any window that wasn't already globally focused. With
        // element: nil, setFrame routes through the helper using pid+windowID.
        guard !snapshot.bounds.isNull, snapshot.bounds.width > 0, snapshot.bounds.height > 0 else {
            throw ProviderError.missingFrame
        }

        let normalFrame = snapshot.bounds.gojoScreenFlipped
        let windowScreen = NSScreen.screen(containing: normalFrame) ?? screen

        return FocusedWindow(
            element: nil,
            windowID: snapshot.windowID,
            pid: app.processIdentifier,
            appName: app.localizedName ?? snapshot.ownerName ?? "App",
            bundleIdentifier: app.bundleIdentifier,
            title: nil,
            axFrame: snapshot.bounds,
            normalFrame: normalFrame,
            screen: windowScreen
        )
    }

    // NOTE: do not resolve the focused window via the helper's
    // focusedWindowSnapshot — the helper's NSWorkspace frontmost state is
    // stale inside the XPC service (see focusedWindow(promptIfNeeded:)).

    private func targetApplication() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let topWindows = topWindowSnapshots()

        var applicationsByPID: [pid_t: NSRunningApplication] = [:]
        [frontmost, lastTargetApplication].compactMap { $0 }.forEach { app in
            applicationsByPID[app.processIdentifier] = app
        }
        for window in topWindows where applicationsByPID[window.pid] == nil {
            applicationsByPID[window.pid] = NSRunningApplication(processIdentifier: window.pid)
        }

        let appSnapshots = applicationsByPID.compactMapValues(applicationSnapshot)
        let selectedPID = WindowTargetResolver.resolve(
            frontmost: frontmost.flatMap(applicationSnapshot),
            lastTarget: lastTargetApplication.flatMap(applicationSnapshot),
            topWindows: topWindows,
            applicationsByPID: appSnapshots,
            ownPID: pid_t(ProcessInfo.processInfo.processIdentifier),
            ownBundleID: ownBundleID
        )

        guard let selectedPID,
              let app = applicationsByPID[selectedPID] ?? NSRunningApplication(processIdentifier: selectedPID),
              isTargetApplication(app) else {
            return nil
        }

        rememberTargetApplicationIfNeeded(app)
        return app
    }

    private func rememberTargetApplicationIfNeeded(_ app: NSRunningApplication) {
        guard isTargetApplication(app) else { return }
        lastTargetApplication = app
    }

    private func isTargetApplication(_ app: NSRunningApplication) -> Bool {
        WindowTargetResolver.isTargetApplication(
            applicationSnapshot(for: app),
            ownPID: pid_t(ProcessInfo.processInfo.processIdentifier),
            ownBundleID: ownBundleID
        )
    }

    private func topWindowSnapshots() -> [WindowTargetWindowSnapshot] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        return windowList.compactMap(WindowTargetWindowSnapshot.init(cgWindowInfo:))
            .filter { WindowTargetResolver.isTopLevelWindow($0, ownPID: ownPID) }
    }

    private func preferredTopWindowID(for pid: pid_t) -> CGWindowID? {
        topWindowSnapshots().first { $0.pid == pid }?.windowID
    }

    private func applicationSnapshot(for app: NSRunningApplication) -> WindowTargetApplicationSnapshot {
        WindowTargetApplicationSnapshot(
            pid: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            activationPolicy: windowTargetActivationPolicy(for: app.activationPolicy),
            isTerminated: app.isTerminated
        )
    }

    private func windowTargetActivationPolicy(for policy: NSApplication.ActivationPolicy) -> WindowTargetActivationPolicy {
        switch policy {
        case .regular:
            return .regular
        case .accessory:
            return .accessory
        case .prohibited:
            return .prohibited
        @unknown default:
            return .unknown
        }
    }

    private func bestWindowElement(for appElement: AXUIElement, preferredWindowID: CGWindowID? = nil) -> AXUIElement? {
        if let preferredWindowID,
           let matchingWindow = copyElements(appElement, attribute: kAXWindowsAttribute)?
            .first(where: { isUsableWindow($0) && windowID(of: $0) == preferredWindowID }) {
            return matchingWindow
        }

        let directCandidates = [
            copyElement(appElement, attribute: kAXFocusedWindowAttribute),
            copyElement(appElement, attribute: kAXMainWindowAttribute)
        ]

        for candidate in directCandidates.compactMap({ $0 }) where isUsableWindow(candidate) {
            return candidate
        }

        return copyElements(appElement, attribute: kAXWindowsAttribute)?
            .first(where: isUsableWindow)
    }

    private func isUsableWindow(_ element: AXUIElement) -> Bool {
        if let role = copyString(element, attribute: kAXRoleAttribute), role != kAXWindowRole as String {
            return false
        }
        if copyBool(element, attribute: kAXMinimizedAttribute) == true {
            return false
        }
        guard let frame = frame(of: element), !frame.isNull, frame.width > 0, frame.height > 0 else {
            return false
        }
        return true
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = copyCGPoint(element, attribute: kAXPositionAttribute),
              let size = copyCGSize(element, attribute: kAXSizeAttribute) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func windowID(of element: AXUIElement) -> CGWindowID? {
        var windowID = CGWindowID(0)
        let result = _AXUIElementGetWindow(element, &windowID)
        guard result == .success else { return nil }
        return windowID
    }

    private func setAXFrame(_ frame: CGRect, for element: AXUIElement, pid: pid_t) -> Bool {
        var size = frame.size
        var position = frame.origin

        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let positionValue = AXValueCreate(.cgPoint, &position) else {
            return false
        }

        let appElement = AXUIElementCreateApplication(pid)
        let enhancedUIWasEnabled = copyBool(appElement, attribute: "AXEnhancedUserInterface")
        if enhancedUIWasEnabled == true {
            setBool(false, element: appElement, attribute: "AXEnhancedUserInterface")
        }

        // Same order Rectangle uses: size, position, size. macOS clamps windows during display moves.
        let firstSizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        let positionResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        let secondSizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)

        if enhancedUIWasEnabled == true {
            setBool(true, element: appElement, attribute: "AXEnhancedUserInterface")
        }

        return firstSizeResult == .success && positionResult == .success && secondSizeResult == .success
    }

    private func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func copyElements(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func copyString(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func copyBool(_ element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    @discardableResult
    private func setBool(_ value: Bool, element: AXUIElement, attribute: String) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value as CFBoolean) == .success
    }

    private func copyCGPoint(_ element: AXUIElement, attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }

    private func copyCGSize(_ element: AXUIElement, attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }
}
