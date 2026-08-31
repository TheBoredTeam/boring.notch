//
//  MenuBarItemController.swift
//  BoringNotchXPCHelper
//
//  Discovers and opens menu bar items through the macOS Accessibility tree,
//  and rearranges movable status-item windows through targeted CGEvents.
//

import ApplicationServices
import Cocoa
import CoreGraphics
import OSLog

private let menuBarAccessLogger = Logger(
    subsystem: "theboringteam.boringnotch.helper",
    category: "MenuBarAccess"
)

private struct AccessibilityMenuBarItem {
    let element: AXUIElement
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let applicationName: String
    let childIndex: Int
    let siblingCount: Int
    let identifier: String?
    let title: String?
    let accessibilityDescription: String?
    let frame: CGRect

    var semanticName: String? {
        [title, accessibilityDescription, identifier]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .first
    }

    var displayName: String {
        if bundleIdentifier == "com.apple.controlcenter", let semanticName {
            return semanticName
        }
        if let semanticName,
           semanticName.localizedCaseInsensitiveCompare(applicationName) != .orderedSame {
            return "\(applicationName) — \(semanticName)"
        }
        if siblingCount > 1 {
            return "\(applicationName) \(childIndex + 1)"
        }
        return applicationName
    }

    var stableID: String {
        // Titles and accessibility descriptions often contain live values
        // (temperature, fan speed, network throughput, unread count, and so
        // on). They are presentation data, not identity. Keeping them out of
        // the identifier prevents a refreshed item from being treated as a
        // brand-new item and appended to the end of the user's notch order.
        let stableAccessibilityIdentifier = identifier?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [
            "v2",
            bundleIdentifier ?? "app:\(applicationName)",
            stableAccessibilityIdentifier,
            stableAccessibilityIdentifier.isEmpty ? String(childIndex) : "",
        ].joined(separator: "|")
    }
}

private enum AccessibilityMenuBarError: LocalizedError {
    case accessibilityRequired
    case invalidRequest
    case itemNotFound
    case actionUnsupported
    case actionFailed(AXError)
    case menuUnavailable
    case menuEntryNotFound
    case moveFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            return "Accessibility permission is required to open menu bar items."
        case .invalidRequest:
            return "The menu bar item request was invalid."
        case .itemNotFound:
            return "The menu bar item is no longer available. Refresh and try again."
        case .actionUnsupported:
            return "This menu bar item does not expose an Accessibility press action."
        case .actionFailed(let error):
            return "The menu bar item could not be opened (Accessibility error \(error.rawValue))."
        case .menuUnavailable:
            return "This status item does not expose a standard Accessibility menu."
        case .menuEntryNotFound:
            return "The menu entry changed before it could be selected. Open the menu again."
        case .moveFailed:
            return "macOS did not allow this menu bar item to be moved. Some system items cannot be hidden or rearranged."
        }
    }
}

@MainActor
final class MenuBarItemController {
    static let shared = MenuBarItemController()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let messagingTimeout: Float = 0.2
    private var eventRelays: [UUID: MenuBarEventRelay] = [:]
    private var isMovingMenuBarItem = false

    private init() { }

    func encodedItems() -> Data {
        let accessibilityAuthorized = AXIsProcessTrusted()
        let items = accessibilityAuthorized ? accessibilityMenuBarItems() : []
        let descriptors = items.map(descriptor)

        menuBarAccessLogger.notice(
            "AX discovery items=\(descriptors.count, privacy: .public) trusted=\(accessibilityAuthorized, privacy: .public)"
        )

        return encode(
            MenuBarItemsResponse(
                items: descriptors,
                accessibilityAuthorized: accessibilityAuthorized,
                errorMessage: accessibilityAuthorized && descriptors.isEmpty
                    ? "No menu bar items were exposed through Accessibility."
                    : nil
            )
        )
    }

    func encodedFailure(_ error: Error) -> Data {
        encode(MenuBarActionResponse(success: false, errorMessage: error.localizedDescription))
    }

    func activate(descriptorData: Data) async -> Data {
        guard descriptorData.count <= 64 * 1024,
              let requested = try? decoder.decode(MenuBarItemDescriptor.self, from: descriptorData)
        else {
            return encodedFailure(AccessibilityMenuBarError.invalidRequest)
        }
        guard AXIsProcessTrusted() else {
            return encodedFailure(AccessibilityMenuBarError.accessibilityRequired)
        }

        var lastError: Error = AccessibilityMenuBarError.itemNotFound
        for attempt in 0..<3 {
            guard let item = resolve(requested) else {
                lastError = AccessibilityMenuBarError.itemNotFound
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(120))
                    continue
                }
                break
            }

            var actions: CFArray?
            let actionResult = AXUIElementCopyActionNames(item.element, &actions)
            guard actionResult == .success,
                  let actionNames = actions as? [String],
                  actionNames.contains(kAXPressAction as String)
            else {
                return encodedFailure(AccessibilityMenuBarError.actionUnsupported)
            }

            let result = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
            if result == .success {
                return encode(MenuBarActionResponse(success: true, errorMessage: nil))
            }

            lastError = AccessibilityMenuBarError.actionFailed(result)
            guard result == .cannotComplete, attempt < 2 else { break }
            try? await Task.sleep(for: .milliseconds(120))
        }

        return encodedFailure(lastError)
    }

    func inspectMenu(descriptorData: Data) async -> Data {
        guard descriptorData.count <= 64 * 1024,
              let requested = try? decoder.decode(MenuBarItemDescriptor.self, from: descriptorData)
        else {
            return encode(
                MenuBarMenuResponse(
                    isSupported: false,
                    originalMenuPresented: false,
                    entries: [],
                    errorMessage: AccessibilityMenuBarError.invalidRequest.localizedDescription
                )
            )
        }
        guard AXIsProcessTrusted() else {
            return encode(
                MenuBarMenuResponse(
                    isSupported: false,
                    originalMenuPresented: false,
                    entries: [],
                    errorMessage: AccessibilityMenuBarError.accessibilityRequired.localizedDescription
                )
            )
        }
        guard let item = resolve(requested) else {
            return encode(
                MenuBarMenuResponse(
                    isSupported: false,
                    originalMenuPresented: false,
                    entries: [],
                    errorMessage: AccessibilityMenuBarError.itemNotFound.localizedDescription
                )
            )
        }

        if let menu = childMenu(of: item.element) {
            let entries = menuEntries(in: menu, parentPath: [])
            return encode(
                MenuBarMenuResponse(
                    isSupported: !entries.isEmpty,
                    originalMenuPresented: false,
                    entries: entries,
                    errorMessage: entries.isEmpty
                        ? AccessibilityMenuBarError.menuUnavailable.localizedDescription
                        : nil
                )
            )
        }

        let (openedMenu, _) = await openMenu(for: item.element)
        guard let openedMenu else {
            // AXPress has already been sent. A custom popover may now be on
            // screen even though it does not expose an AXMenu tree, so the app
            // should close its notch and leave that original UI visible.
            return encode(
                MenuBarMenuResponse(
                    isSupported: false,
                    originalMenuPresented: true,
                    entries: [],
                    errorMessage: nil
                )
            )
        }

        let entries = menuEntries(in: openedMenu, parentPath: [])
        _ = AXUIElementPerformAction(openedMenu, kAXCancelAction as CFString)
        return encode(
            MenuBarMenuResponse(
                isSupported: !entries.isEmpty,
                originalMenuPresented: false,
                entries: entries,
                errorMessage: entries.isEmpty
                    ? AccessibilityMenuBarError.menuUnavailable.localizedDescription
                    : nil
            )
        )
    }

    func activateMenuEntry(requestData: Data) async -> Data {
        guard requestData.count <= 128 * 1024,
              let request = try? decoder.decode(MenuBarMenuActionRequest.self, from: requestData)
        else {
            return encodedFailure(AccessibilityMenuBarError.invalidRequest)
        }
        guard AXIsProcessTrusted() else {
            return encodedFailure(AccessibilityMenuBarError.accessibilityRequired)
        }
        guard request.entry.isEnabled, !request.entry.isSeparator else {
            return encodedFailure(AccessibilityMenuBarError.actionUnsupported)
        }
        guard let item = resolve(request.item) else {
            return encodedFailure(AccessibilityMenuBarError.itemNotFound)
        }
        let menuWasAlreadyAvailable = childMenu(of: item.element)
        let menu: AXUIElement
        if let menuWasAlreadyAvailable {
            menu = menuWasAlreadyAvailable
        } else {
            let (openedMenu, _) = await openMenu(for: item.element)
            guard let openedMenu else {
                return encodedFailure(AccessibilityMenuBarError.menuUnavailable)
            }
            menu = openedMenu
        }
        guard let target = menuItem(at: request.entry.path, in: menu) else {
            if menuWasAlreadyAvailable == nil {
                _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            }
            return encodedFailure(AccessibilityMenuBarError.menuEntryNotFound)
        }

        let currentTitle = menuItemTitle(target)
        guard currentTitle == request.entry.title else {
            if menuWasAlreadyAvailable == nil {
                _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            }
            return encodedFailure(AccessibilityMenuBarError.menuEntryNotFound)
        }

        let result = AXUIElementPerformAction(target, kAXPickAction as CFString)
        if result == .success || result == .cannotComplete {
            return encode(MenuBarActionResponse(success: true, errorMessage: nil))
        }

        if menuWasAlreadyAvailable == nil {
            _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        }
        return encodedFailure(AccessibilityMenuBarError.actionFailed(result))
    }

    func move(requestData: Data) async -> Data {
        guard requestData.count <= 64 * 1024,
              let request = try? decoder.decode(MenuBarItemMoveRequest.self, from: requestData),
              request.sourceWindowID != request.targetWindowID,
              request.sourceProcessIdentifier > 0,
              request.sourceFrameWidth > 0,
              request.sourceFrameHeight > 0,
              request.targetFrameWidth > 0,
              request.targetFrameHeight > 0 else {
            return encodedFailure(AccessibilityMenuBarError.invalidRequest)
        }
        guard AXIsProcessTrusted() else {
            return encodedFailure(AccessibilityMenuBarError.accessibilityRequired)
        }
        guard !isMovingMenuBarItem else {
            return encodedFailure(AccessibilityMenuBarError.moveFailed)
        }
        isMovingMenuBarItem = true
        defer { isMovingMenuBarItem = false }

        let sourceFrame = CGRect(
            x: request.sourceFrameX,
            y: request.sourceFrameY,
            width: request.sourceFrameWidth,
            height: request.sourceFrameHeight
        )
        let targetFrame = CGRect(
            x: request.targetFrameX,
            y: request.targetFrameY,
            width: request.targetFrameWidth,
            height: request.targetFrameHeight
        )

        // Status items without their own WindowServer window cannot receive a
        // targeted drag. Move only items whose AXPosition is explicitly
        // writable; never fall back to moving the global mouse pointer.
        if request.sourceWindowID == 0 {
            guard let descriptor = request.item,
                  let item = resolve(descriptor),
                  setAccessibilityPosition(
                    for: item.element,
                    sourceFrame: sourceFrame,
                    targetFrame: targetFrame,
                    placement: request.placement
                  ) else {
                return encodedFailure(AccessibilityMenuBarError.moveFailed)
            }
            try? await Task.sleep(for: .milliseconds(100))
            return encode(MenuBarActionResponse(success: true, errorMessage: nil))
        }

        let processIdentifier = pid_t(request.sourceProcessIdentifier)
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            return encodedFailure(AccessibilityMenuBarError.moveFailed)
        }

        permitLocalEventsDuringSyntheticDrag()

        for attempt in 1...3 {
            let liveSourceFrame = currentWindowFrame(
                windowID: request.sourceWindowID
            ) ?? sourceFrame
            let liveTargetFrame = currentWindowFrame(
                windowID: request.targetWindowID
            ) ?? targetFrame

            if placementIsSatisfied(
                request.placement,
                sourceFrame: liveSourceFrame,
                targetFrame: liveTargetFrame
            ) {
                return encode(MenuBarActionResponse(success: true, errorMessage: nil))
            }

            let points = targetPoints(
                sourceFrame: liveSourceFrame,
                targetFrame: liveTargetFrame,
                placement: request.placement
            )
            guard let mouseDown = menuBarMoveEvent(
                type: .leftMouseDown,
                location: points.start,
                windowID: request.sourceWindowID,
                processIdentifier: processIdentifier,
                source: eventSource,
                command: true
            ), let mouseUp = menuBarMoveEvent(
                type: .leftMouseUp,
                location: points.end,
                windowID: request.targetWindowID,
                processIdentifier: processIdentifier,
                source: eventSource,
                command: false
            ) else {
                return encodedFailure(AccessibilityMenuBarError.moveFailed)
            }

            menuBarAccessLogger.notice(
                "Move attempt=\(attempt, privacy: .public) sourceWindow=\(request.sourceWindowID, privacy: .public) targetWindow=\(request.targetWindowID, privacy: .public) eventPID=\(processIdentifier, privacy: .public)"
            )

            guard await relay(mouseDown, to: processIdentifier) else {
                menuBarAccessLogger.error(
                    "Menu bar mouse-down barrier failed attempt=\(attempt, privacy: .public)"
                )
                // The real mouse-down may already have reached WindowServer
                // even when only the final acknowledgement was lost. Always
                // release it through the full relay before trying again.
                _ = await relay(
                    mouseUp,
                    to: processIdentifier,
                    repetitions: 2
                )
                try? await Task.sleep(for: .milliseconds(60))
                break
            }

            guard await waitForFrameChange(
                windowID: request.sourceWindowID,
                initialOrigin: liveSourceFrame.origin,
                timeoutMilliseconds: 160
            ) else {
                menuBarAccessLogger.error(
                    "Menu bar item did not acknowledge mouse-down attempt=\(attempt, privacy: .public)"
                )
                _ = await relay(
                    mouseUp,
                    to: processIdentifier,
                    repetitions: 2
                )
                try? await Task.sleep(for: .milliseconds(60))
                break
            }
            let originAfterMouseDown = currentWindowFrame(
                windowID: request.sourceWindowID
            )?.origin ?? liveSourceFrame.origin

            guard await relay(
                mouseUp,
                to: processIdentifier,
                repetitions: 2
            ) else {
                menuBarAccessLogger.error(
                    "Menu bar mouse-up barrier failed attempt=\(attempt, privacy: .public)"
                )
                // Use the same acknowledged three-stage route for cleanup.
                // A raw session post can leave WindowServer believing that a
                // synthetic Command-drag is still active.
                _ = await relay(
                    mouseUp,
                    to: processIdentifier,
                    repetitions: 2
                )
                try? await Task.sleep(for: .milliseconds(60))
                break
            }

            _ = await waitForFrameChange(
                windowID: request.sourceWindowID,
                initialOrigin: originAfterMouseDown,
                timeoutMilliseconds: 160
            )
            try? await Task.sleep(for: .milliseconds(40))

            if let movedSourceFrame = currentWindowFrame(
                windowID: request.sourceWindowID
            ), let movedTargetFrame = currentWindowFrame(
                windowID: request.targetWindowID
            ), placementIsSatisfied(
                request.placement,
                sourceFrame: movedSourceFrame,
                targetFrame: movedTargetFrame
            ) {
                menuBarAccessLogger.notice(
                    "Menu bar move verified attempt=\(attempt, privacy: .public)"
                )
                return encode(MenuBarActionResponse(success: true, errorMessage: nil))
            }

            try? await Task.sleep(for: .milliseconds(80))
        }

        // There is no API for assigning the order of another application's
        // NSStatusItem. If macOS refuses the window-targeted Ice-style relay
        // from an embedded XPC service, fall back to the same physical
        // Command-drag gesture the user can perform manually. Only that short
        // fallback section hides and restores the cursor; the targeted relay
        // above never disturbs the physical pointer.
        let fallbackSourceFrame = currentWindowFrame(
            windowID: request.sourceWindowID
        ) ?? sourceFrame
        let fallbackTargetFrame = currentWindowFrame(
            windowID: request.targetWindowID
        ) ?? targetFrame
        guard await waitForUserInputToPause() else {
            menuBarAccessLogger.error(
                "HID fallback cancelled because user input did not become idle"
            )
            return encodedFailure(AccessibilityMenuBarError.moveFailed)
        }
        if await performHIDCommandDrag(
            sourceFrame: fallbackSourceFrame,
            targetFrame: fallbackTargetFrame,
            placement: request.placement
        ) {
            try? await Task.sleep(for: .milliseconds(180))
            if let movedSourceFrame = currentWindowFrame(
                windowID: request.sourceWindowID
            ), let movedTargetFrame = currentWindowFrame(
                windowID: request.targetWindowID
            ), placementIsSatisfied(
                request.placement,
                sourceFrame: movedSourceFrame,
                targetFrame: movedTargetFrame
            ) {
                menuBarAccessLogger.notice("Menu bar move verified through HID fallback")
                return encode(MenuBarActionResponse(success: true, errorMessage: nil))
            }
        }

        menuBarAccessLogger.error("Menu bar move failed after all attempts")
        return encodedFailure(AccessibilityMenuBarError.moveFailed)
    }

    private func menuBarMoveEvent(
        type: CGEventType,
        location: CGPoint,
        windowID: UInt32,
        processIdentifier: pid_t,
        source: CGEventSource,
        command: Bool
    ) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else {
            return nil
        }

        event.flags = command ? .maskCommand : []
        event.setIntegerValueField(
            .eventTargetUnixProcessID,
            value: Int64(processIdentifier)
        )
        event.setIntegerValueField(
            .eventSourceUserData,
            // Keep the marker in the range that survives every WindowServer
            // event serialization path. It only needs to be unique among the
            // handful of active relays.
            value: Int64(UInt32.random(in: 1...UInt32.max))
        )
        event.setIntegerValueField(
            .mouseEventWindowUnderMousePointer,
            value: Int64(windowID)
        )
        event.setIntegerValueField(
            .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
            value: Int64(windowID)
        )
        event.setIntegerValueField(.menuBarWindowID, value: Int64(windowID))
        return event
    }

    private func relay(
        _ event: CGEvent,
        to processIdentifier: pid_t,
        repetitions: Int = 1
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let identifier = UUID()
            guard let relay = MenuBarEventRelay(
                event: event,
                processIdentifier: processIdentifier,
                repetitions: repetitions,
                completion: { [weak self] success in
                    Task { @MainActor in
                        self?.eventRelays[identifier] = nil
                        continuation.resume(returning: success)
                    }
                }
            ) else {
                continuation.resume(returning: false)
                return
            }
            eventRelays[identifier] = relay
            relay.start()
        }
    }

    private func targetPoints(
        sourceFrame: CGRect,
        targetFrame: CGRect,
        placement: MenuBarItemMovePlacement
    ) -> (start: CGPoint, end: CGPoint) {
        switch placement {
        case .leftOfTarget:
            var start = CGPoint(x: targetFrame.minX, y: targetFrame.minY)
            var end = start
            if sourceFrame.maxX <= targetFrame.minX {
                end.x -= sourceFrame.width
            } else {
                start.x -= 1
            }
            return (start, end)

        case .rightOfTarget:
            var start = CGPoint(x: targetFrame.maxX, y: targetFrame.minY)
            var end = start
            if sourceFrame.minX <= targetFrame.maxX {
                end.x -= sourceFrame.width
            } else {
                start.x += 1
            }
            return (start, end)
        }
    }

    private func currentWindowFrame(windowID: CGWindowID) -> CGRect? {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow, .excludeDesktopElements],
            windowID
        ) as? [[CFString: Any]],
        let bounds = windowInfo.first?[kCGWindowBounds] as? NSDictionary else {
            return nil
        }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    private func placementIsSatisfied(
        _ placement: MenuBarItemMovePlacement,
        sourceFrame: CGRect,
        targetFrame: CGRect
    ) -> Bool {
        let tolerance: CGFloat = 1.5
        switch placement {
        case .leftOfTarget:
            return abs(sourceFrame.maxX - targetFrame.minX) <= tolerance
        case .rightOfTarget:
            return abs(sourceFrame.minX - targetFrame.maxX) <= tolerance
        }
    }

    /// Performs a short, human-shaped Command-drag through the HID event tap.
    /// This is adapted from SaneBar's AccessibilityMenuBarDragService and is
    /// used only when the no-pointer WindowServer relay cannot be acknowledged.
    private func performHIDCommandDrag(
        sourceFrame: CGRect,
        targetFrame: CGRect,
        placement: MenuBarItemMovePlacement
    ) async -> Bool {
        let sourcePoint = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        // Drop immediately beside the compact 18-point boundary. A larger
        // offset can cross the neighboring status item and report the wrong
        // order even though the requested side was reached.
        let insertionOffset: CGFloat = 3
        let targetPoint = CGPoint(
            x: placement == .leftOfTarget
                ? targetFrame.minX - insertionOffset
                : targetFrame.maxX + insertionOffset,
            y: targetFrame.midY
        )

        guard let displayID = displayContaining(sourcePoint),
              displayContaining(targetPoint) == displayID else {
            menuBarAccessLogger.error(
                "HID fallback points are not on the same display source=(\(sourcePoint.x, privacy: .public),\(sourcePoint.y, privacy: .public)) target=(\(targetPoint.x, privacy: .public),\(targetPoint.y, privacy: .public))"
            )
            return false
        }
        guard !pathCrossesNotch(
            from: sourcePoint,
            to: targetPoint,
            on: displayID
        ) else {
            menuBarAccessLogger.error(
                "HID fallback path crosses the display notch"
            )
            return false
        }
        guard !CGEventSource.buttonState(.combinedSessionState, button: .left),
              !Task.isCancelled else {
            return false
        }

        menuBarAccessLogger.notice(
            "Starting hidden-cursor HID fallback source=(\(sourcePoint.x, privacy: .public),\(sourcePoint.y, privacy: .public)) target=(\(targetPoint.x, privacy: .public),\(targetPoint.y, privacy: .public))"
        )

        let originalPointerLocation = CGEvent(source: nil)?.location
        let cursorWasHidden = CGDisplayHideCursor(displayID) == .success
        defer {
            if let originalPointerLocation {
                _ = CGWarpMouseCursorPosition(originalPointerLocation)
            }
            if cursorWasHidden {
                _ = CGDisplayShowCursor(displayID)
            }
        }

        guard let preposition = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: sourcePoint,
            mouseButton: .left
        ) else { return false }
        preposition.post(tap: .cghidEventTap)
        guard await sleepUnlessCancelled(for: .milliseconds(60)),
              !CGEventSource.buttonState(.combinedSessionState, button: .left) else {
            return false
        }

        guard let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: sourcePoint,
            mouseButton: .left
        ) else { return false }
        mouseDown.flags = .maskCommand
        mouseDown.post(tap: .cghidEventTap)

        var mouseIsDown = true
        var lastPostedPoint = sourcePoint
        defer {
            if mouseIsDown,
               let forcedMouseUp = CGEvent(
                   mouseEventSource: nil,
                   mouseType: .leftMouseUp,
                   mouseCursorPosition: lastPostedPoint,
                   mouseButton: .left
               ) {
                forcedMouseUp.post(tap: .cghidEventTap)
            }
        }

        guard await sleepUnlessCancelled(for: .milliseconds(80)) else {
            return false
        }
        let distance = hypot(targetPoint.x - sourcePoint.x, targetPoint.y - sourcePoint.y)
        let stepCount = min(max(Int(ceil(distance / 22)), 10), 14)
        for step in 1...stepCount {
            let progress = CGFloat(step) / CGFloat(stepCount)
            let point = CGPoint(
                x: sourcePoint.x + (targetPoint.x - sourcePoint.x) * progress,
                y: sourcePoint.y + (targetPoint.y - sourcePoint.y) * progress
            )
            guard let drag = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else { return false }
            drag.flags = .maskCommand
            drag.post(tap: .cghidEventTap)
            lastPostedPoint = point
            guard await sleepUnlessCancelled(for: .milliseconds(15)) else {
                return false
            }
        }

        guard let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: targetPoint,
            mouseButton: .left
        ) else { return false }
        mouseUp.flags = .maskCommand
        mouseUp.post(tap: .cghidEventTap)
        mouseIsDown = false
        return await sleepUnlessCancelled(for: .milliseconds(140))
    }

    private func displayContaining(_ point: CGPoint) -> CGDirectDisplayID? {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displays, &displayCount) == .success else {
            return nil
        }
        return displays.prefix(Int(displayCount)).first {
            CGDisplayBounds($0).contains(point)
        }
    }

    private func pathCrossesNotch(
        from sourcePoint: CGPoint,
        to targetPoint: CGPoint,
        on displayID: CGDirectDisplayID
    ) -> Bool {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                == displayID
        }), let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea else {
            return false
        }

        let notchMinX = leftArea.maxX
        let notchMaxX = rightArea.minX
        guard notchMaxX > notchMinX else { return false }

        return (sourcePoint.x < notchMinX && targetPoint.x > notchMaxX)
            || (targetPoint.x < notchMinX && sourcePoint.x > notchMaxX)
    }

    private func waitForFrameChange(
        windowID: CGWindowID,
        initialOrigin: CGPoint,
        timeoutMilliseconds: Int
    ) async -> Bool {
        let checks = max(1, timeoutMilliseconds / 5)
        for _ in 0..<checks {
            if currentWindowFrame(windowID: windowID)?.origin != initialOrigin {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    private func waitForUserInputToPause() async -> Bool {
        var consecutiveIdleSamples = 0
        for _ in 0..<12 {
            guard !Task.isCancelled else { return false }
            guard !CGEventSource.buttonState(.combinedSessionState, button: .left),
                  let first = CGEvent(source: nil)?.location else {
                consecutiveIdleSamples = 0
                guard await sleepUnlessCancelled(for: .milliseconds(30)) else {
                    return false
                }
                continue
            }
            guard await sleepUnlessCancelled(for: .milliseconds(30)),
                  !CGEventSource.buttonState(.combinedSessionState, button: .left),
                  let second = CGEvent(source: nil)?.location else {
                consecutiveIdleSamples = 0
                continue
            }
            if hypot(second.x - first.x, second.y - first.y) <= 2 {
                consecutiveIdleSamples += 1
                if consecutiveIdleSamples >= 2 {
                    return true
                }
            } else {
                consecutiveIdleSamples = 0
            }
        }
        return false
    }

    private func sleepUnlessCancelled(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func permitLocalEventsDuringSyntheticDrag() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }
        let mask: CGEventFilterMask = [
            .permitLocalMouseEvents,
            .permitLocalKeyboardEvents,
            .permitSystemDefinedEvents,
        ]
        source.setLocalEventsFilterDuringSuppressionState(
            mask,
            state: .eventSuppressionStateRemoteMouseDrag
        )
        source.setLocalEventsFilterDuringSuppressionState(
            mask,
            state: .eventSuppressionStateSuppressionInterval
        )
        source.localEventsSuppressionInterval = 0
    }

    private func setAccessibilityPosition(
        for element: AXUIElement,
        sourceFrame: CGRect,
        targetFrame: CGRect,
        placement: MenuBarItemMovePlacement
    ) -> Bool {
        var isSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXPositionAttribute as CFString,
            &isSettable
        ) == .success,
        isSettable.boolValue else {
            return false
        }

        var position = CGPoint(
            x: placement == .leftOfTarget
                ? targetFrame.minX - sourceFrame.width
                : targetFrame.maxX,
            y: sourceFrame.minY
        )
        guard let value = AXValueCreate(.cgPoint, &position) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            value
        ) == .success
    }

    // MARK: - Accessibility discovery

    private func accessibilityMenuBarItems() -> [AccessibilityMenuBarItem] {
        let result = NSWorkspace.shared.runningApplications.flatMap(accessibilityMenuBarItems)

        return result.sorted { lhs, rhs in
            let lhsHasFrame = lhs.frame.width > 0 && lhs.frame.height > 0
            let rhsHasFrame = rhs.frame.width > 0 && rhs.frame.height > 0
            if lhsHasFrame != rhsHasFrame { return lhsHasFrame }
            if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
            if lhs.frame.minX != rhs.frame.minX { return lhs.frame.minX < rhs.frame.minX }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func accessibilityMenuBarItems(
        for application: NSRunningApplication
    ) -> [AccessibilityMenuBarItem] {
        guard application.isFinishedLaunching, !application.isTerminated else { return [] }
        guard !(application.bundleIdentifier ?? "").hasPrefix("theboringteam.boringnotch") else {
            return []
        }

        let isApplicationBundle = application.bundleURL?.pathExtension == "app"
        guard application.activationPolicy != .prohibited || isApplicationBundle else { return [] }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, messagingTimeout)
        guard let extrasMenuBar: AXUIElement = attribute(
            applicationElement,
            kAXExtrasMenuBarAttribute as CFString
        ) else {
            return []
        }
        AXUIElementSetMessagingTimeout(extrasMenuBar, messagingTimeout)
        guard let children: [AXUIElement] = attribute(
            extrasMenuBar,
            kAXChildrenAttribute as CFString
        ), !children.isEmpty else {
            return []
        }

        let pressableChildren: [(Int, AXUIElement)] = children.enumerated().compactMap { index, child in
            guard let role: String = attribute(child, kAXRoleAttribute as CFString),
                  role == kAXMenuBarItemRole as String else {
                return nil
            }
            var actions: CFArray?
            guard AXUIElementCopyActionNames(child, &actions) == .success,
                  let actionNames = actions as? [String],
                  actionNames.contains(kAXPressAction as String) else {
                return nil
            }
            return (index, child)
        }

        return pressableChildren.compactMap { index, child in
            let identifier: String? = attribute(child, kAXIdentifierAttribute as CFString)
            let title: String? = attribute(child, kAXTitleAttribute as CFString)
            let accessibilityDescription: String? = attribute(
                child,
                kAXDescriptionAttribute as CFString
            )
            let itemFrame = frame(of: child) ?? .zero
            let hasSemanticName = [identifier, title, accessibilityDescription].contains { value in
                value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
            // Tahoe exposes placeholder Control Center children for menu
            // extras that are not configured. They have no identity and a
            // zero-sized frame, so they are not actionable choices for UI.
            if application.bundleIdentifier == "com.apple.controlcenter",
               !hasSemanticName,
               itemFrame.width <= 0,
               itemFrame.height <= 0 {
                return nil
            }

            return AccessibilityMenuBarItem(
                element: child,
                processIdentifier: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.localizedName
                    ?? application.bundleIdentifier
                    ?? "Menu Bar Item",
                childIndex: index,
                siblingCount: pressableChildren.count,
                identifier: identifier,
                title: title,
                accessibilityDescription: accessibilityDescription,
                frame: itemFrame
            )
        }
    }

    // MARK: - Standard menu mirroring

    private func openMenu(for statusItem: AXUIElement) async -> (AXUIElement?, AXError) {
        let pressResult = AXUIElementPerformAction(statusItem, kAXPressAction as CFString)
        for attempt in 0..<10 {
            if let menu = childMenu(of: statusItem) {
                return (menu, pressResult)
            }
            if attempt < 9 {
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
        return (nil, pressResult)
    }

    private func childMenu(of element: AXUIElement) -> AXUIElement? {
        let children: [AXUIElement] = attribute(element, kAXChildrenAttribute as CFString) ?? []
        return children.first(where: {
            let role: String? = attribute($0, kAXRoleAttribute as CFString)
            return role == kAXMenuRole as String
        })
    }

    private func menuItemChildren(of menu: AXUIElement) -> [AXUIElement] {
        let children: [AXUIElement] = attribute(menu, kAXChildrenAttribute as CFString) ?? []
        return children.filter {
            let role: String? = attribute($0, kAXRoleAttribute as CFString)
            return role == kAXMenuItemRole as String
        }
    }

    private func menuEntries(
        in menu: AXUIElement,
        parentPath: [Int]
    ) -> [MenuBarMenuEntry] {
        menuItemChildren(of: menu).enumerated().map { index, item in
            let path = parentPath + [index]
            let title = menuItemTitle(item)
            let enabled: Bool = attribute(item, kAXEnabledAttribute as CFString) ?? false
            let mark: String? = attribute(item, kAXMenuItemMarkCharAttribute as CFString)
            let keyEquivalent: String? = attribute(item, kAXMenuItemCmdCharAttribute as CFString)
            let modifierValue: NSNumber? = attribute(
                item,
                kAXMenuItemCmdModifiersAttribute as CFString
            )
            let submenu = childMenu(of: item)
            return MenuBarMenuEntry(
                id: path.map(String.init).joined(separator: "."),
                path: path,
                title: title,
                isEnabled: enabled,
                isSeparator: title.isEmpty,
                isMarked: mark?.isEmpty == false,
                keyEquivalent: keyEquivalent?.isEmpty == false ? keyEquivalent : nil,
                keyEquivalentModifiers: modifierValue?.uint32Value ?? 0,
                children: submenu.map { menuEntries(in: $0, parentPath: path) } ?? []
            )
        }
    }

    private func menuItem(at path: [Int], in rootMenu: AXUIElement) -> AXUIElement? {
        guard !path.isEmpty else { return nil }
        var menu = rootMenu
        var item: AXUIElement?
        for (depth, index) in path.enumerated() {
            let items = menuItemChildren(of: menu)
            guard items.indices.contains(index) else { return nil }
            item = items[index]
            if depth < path.count - 1 {
                guard let nextMenu = childMenu(of: items[index]) else { return nil }
                menu = nextMenu
            }
        }
        return item
    }

    private func menuItemTitle(_ item: AXUIElement) -> String {
        let candidates: [String?] = [
            attribute(item, kAXTitleAttribute as CFString),
            attribute(item, kAXValueAttribute as CFString),
            attribute(item, kAXDescriptionAttribute as CFString),
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private func resolve(_ descriptor: MenuBarItemDescriptor) -> AccessibilityMenuBarItem? {
        let applications = NSWorkspace.shared.runningApplications
        if let exactApplication = applications.first(where: {
            $0.processIdentifier == pid_t(descriptor.processIdentifier)
        }), let item = resolve(
            descriptor,
            in: accessibilityMenuBarItems(for: exactApplication)
        ) {
            return item
        }

        guard let bundleIdentifier = descriptor.bundleIdentifier else { return nil }
        let matchingItems = applications
            .filter { $0.bundleIdentifier == bundleIdentifier }
            .flatMap(accessibilityMenuBarItems)
        return resolve(descriptor, in: matchingItems)
    }

    private func resolve(
        _ descriptor: MenuBarItemDescriptor,
        in items: [AccessibilityMenuBarItem]
    ) -> AccessibilityMenuBarItem? {
        if let exact = items.first(where: {
            $0.stableID == descriptor.id
                && $0.processIdentifier == pid_t(descriptor.processIdentifier)
        }) {
            return exact
        }
        if let stable = items.first(where: { $0.stableID == descriptor.id }) {
            return stable
        }
        return items.first(where: {
            $0.bundleIdentifier == descriptor.bundleIdentifier
                && $0.displayName == descriptor.displayName
        })
    }

    private func descriptor(for item: AccessibilityMenuBarItem) -> MenuBarItemDescriptor {
        MenuBarItemDescriptor(
            id: item.stableID,
            processIdentifier: item.processIdentifier,
            bundleIdentifier: item.bundleIdentifier,
            applicationName: item.applicationName,
            accessibilityIdentifier: item.identifier,
            title: item.semanticName,
            displayName: item.displayName,
            frameX: item.frame.origin.x,
            frameY: item.frame.origin.y,
            frameWidth: item.frame.width,
            frameHeight: item.frame.height
        )
    }

    private func attribute<T>(_ element: AXUIElement, _ name: CFString) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = attribute(element, kAXPositionAttribute as CFString),
              let sizeValue: AXValue = attribute(element, kAXSizeAttribute as CFString) else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }
}

private extension CGEventField {
    // WindowServer uses this field for Command-dragged status-item events.
    static let menuBarWindowID = CGEventField(rawValue: 0x33)!
}
