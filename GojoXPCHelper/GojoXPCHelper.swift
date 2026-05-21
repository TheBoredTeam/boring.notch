//
//  GojoXPCHelper.swift
//  GojoXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import ApplicationServices
import IOKit
import CoreGraphics
import AppKit

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

class GojoXPCHelper: NSObject, GojoXPCHelperProtocol {
    private var activationObserver: Any?
    private var lastWindowTargetApplication: NSRunningApplication?

    override init() {
        super.init()

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.rememberTargetApplicationIfNeeded(app)
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
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }

    @objc func focusedWindowSnapshot(_ promptIfNeeded: Bool, with reply: @escaping (NSDictionary) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                reply(["authorized": false, "error": "helperUnavailable"])
                return
            }

            guard self.ensureAccessibilityAuthorizationSync(promptIfNeeded: promptIfNeeded) else {
                reply(["authorized": false, "error": "permissionMissing"])
                return
            }

            guard let snapshot = self.focusedWindowSnapshotDictionary() else {
                reply(["authorized": true, "error": "noFocusedWindow"])
                return
            }

            reply(snapshot)
        }
    }

    @objc func setFocusedWindowFrame(_ normalFrame: NSDictionary, windowID: NSNumber?, with reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  AXIsProcessTrusted(),
                  let frame = CGRect(dictionaryRepresentation: normalFrame as CFDictionary),
                  let app = self.targetApplication() else {
                reply(false)
                return
            }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let windowElement = self.bestWindowElement(
                for: appElement,
                preferredWindowID: windowID.map { CGWindowID(truncating: $0) }
            ) else {
                reply(false)
                return
            }

            reply(self.setAXFrame(frame.gojoHelperScreenFlipped, for: windowElement, pid: app.processIdentifier))
        }
    }

    @objc func setWindowFrame(_ normalFrame: NSDictionary, pid: NSNumber, windowID: NSNumber?, with reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  AXIsProcessTrusted(),
                  let frame = CGRect(dictionaryRepresentation: normalFrame as CFDictionary) else {
                reply(false)
                return
            }

            let pidValue = pid_t(truncating: pid)
            let appElement = AXUIElementCreateApplication(pidValue)
            let cgID = windowID.map { CGWindowID(truncating: $0) }
            guard let windowElement = self.windowElement(for: appElement, exactWindowID: cgID)
                ?? self.bestWindowElement(for: appElement, preferredWindowID: cgID) else {
                reply(false)
                return
            }
            reply(self.setAXFrame(frame.gojoHelperScreenFlipped, for: windowElement, pid: pidValue))
        }
    }

    @objc func performZoom(_ pid: NSNumber, windowID: NSNumber?, with reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, AXIsProcessTrusted() else {
                reply(false)
                return
            }
            let pidValue = pid_t(truncating: pid)
            let appElement = AXUIElementCreateApplication(pidValue)
            let cgID = windowID.map { CGWindowID(truncating: $0) }
            guard let windowElement = self.windowElement(for: appElement, exactWindowID: cgID)
                ?? self.bestWindowElement(for: appElement, preferredWindowID: cgID) else {
                reply(false)
                return
            }

            var buttonValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(windowElement, kAXZoomButtonAttribute as CFString, &buttonValue) == .success,
                  let value = buttonValue,
                  CFGetTypeID(value) == AXUIElementGetTypeID() else {
                reply(false)
                return
            }
            let zoomButton = value as! AXUIElement
            reply(AXUIElementPerformAction(zoomButton, kAXPressAction as CFString) == .success)
        }
    }

    @objc func raiseWindow(_ pid: NSNumber, windowID: NSNumber?, with reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, AXIsProcessTrusted() else {
                reply(false)
                return
            }
            let pidValue = pid_t(truncating: pid)
            let appElement = AXUIElementCreateApplication(pidValue)
            let cgID = windowID.map { CGWindowID(truncating: $0) }
            let element = self.windowElement(for: appElement, exactWindowID: cgID)
                ?? self.bestWindowElement(for: appElement, preferredWindowID: cgID)

            if let element {
                AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            }
            AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            reply(element != nil)
        }
    }

    @objc func enumerateWindows(forScreen screenUUID: NSString?, with reply: @escaping (NSArray) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, AXIsProcessTrusted() else {
                reply([] as NSArray)
                return
            }

            let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
            let snapshots = self.topWindowSnapshots()
            let excludedBundleIDs: Set<String> = [
                "rohoswagger.gojo",
                "rohoswagger.gojo.GojoXPCHelper",
                Bundle.main.bundleIdentifier ?? ""
            ].filter { !$0.isEmpty }.reduce(into: Set<String>()) { $0.insert($1) }

            var seen: Set<UInt32> = []
            let results: [NSDictionary] = snapshots.compactMap { snapshot -> NSDictionary? in
                guard WindowTargetResolver.isTopLevelWindow(snapshot, ownPID: ownPID) else { return nil }
                guard snapshot.bounds.width >= 200, snapshot.bounds.height >= 120 else { return nil }
                guard let app = NSRunningApplication(processIdentifier: snapshot.pid),
                      app.activationPolicy == .regular,
                      WindowTargetResolver.isTargetApplication(
                        WindowTargetApplicationSnapshot(
                            pid: app.processIdentifier,
                            bundleIdentifier: app.bundleIdentifier,
                            activationPolicy: .regular,
                            isTerminated: app.isTerminated
                        ),
                        ownPID: ownPID,
                        excludedBundleIDs: excludedBundleIDs
                      ) else { return nil }

                if let wid = snapshot.windowID {
                    guard seen.insert(wid).inserted else { return nil }
                }

                let normalFrame = snapshot.bounds.gojoHelperScreenFlipped
                let dict: [String: Any] = [
                    "pid": NSNumber(value: snapshot.pid),
                    "windowID": snapshot.windowID.map { NSNumber(value: $0) } as Any,
                    "appName": app.localizedName ?? snapshot.ownerName ?? "App",
                    "bundleIdentifier": app.bundleIdentifier ?? "",
                    "bounds": NSDictionary(dictionary: snapshot.bounds.dictionaryRepresentation as NSDictionary),
                    "normalFrame": NSDictionary(dictionary: normalFrame.dictionaryRepresentation as NSDictionary)
                ]
                return dict as NSDictionary
            }

            reply(results as NSArray)
        }
    }

    private func windowElement(for appElement: AXUIElement, exactWindowID: CGWindowID?) -> AXUIElement? {
        guard let cgID = exactWindowID else { return nil }
        guard let windows = copyElements(appElement, attribute: kAXWindowsAttribute) else { return nil }
        return windows.first { isUsableWindow($0) && windowID(of: $0) == cgID }
    }

    private func ensureAccessibilityAuthorizationSync(promptIfNeeded: Bool) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }
        return AXIsProcessTrusted()
    }

    private func focusedWindowSnapshotDictionary() -> NSDictionary? {
        guard let app = targetApplication() else {
            return nil
        }

        rememberTargetApplicationIfNeeded(app)

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let preferredWindowID = preferredTopWindowID(for: app.processIdentifier)
        guard let windowElement = bestWindowElement(for: appElement, preferredWindowID: preferredWindowID),
              let axFrame = frame(of: windowElement),
              !axFrame.isNull,
              axFrame.width > 0,
              axFrame.height > 0 else {
            return nil
        }

        let normalFrame = axFrame.gojoHelperScreenFlipped
        let windowID = windowID(of: windowElement) ?? preferredWindowID
        var snapshot: [String: Any] = [
            "authorized": true,
            "pid": NSNumber(value: app.processIdentifier),
            "appName": app.localizedName ?? "Focused app",
            "axFrame": axFrame.dictionaryRepresentation as NSDictionary,
            "normalFrame": normalFrame.dictionaryRepresentation as NSDictionary
        ]

        if let windowID {
            snapshot["windowID"] = NSNumber(value: windowID)
        }

        if let bundleIdentifier = app.bundleIdentifier {
            snapshot["bundleIdentifier"] = bundleIdentifier
        }
        if let title = copyString(windowElement, attribute: kAXTitleAttribute) {
            snapshot["title"] = title
        }

        return snapshot as NSDictionary
    }

    private func targetApplication() -> NSRunningApplication? {
        let frontmost = focusedApplication() ?? NSWorkspace.shared.frontmostApplication
        let topWindows = topWindowSnapshots()

        var applicationsByPID: [pid_t: NSRunningApplication] = [:]
        [frontmost, lastWindowTargetApplication].compactMap { $0 }.forEach { app in
            applicationsByPID[app.processIdentifier] = app
        }
        for window in topWindows where applicationsByPID[window.pid] == nil {
            applicationsByPID[window.pid] = NSRunningApplication(processIdentifier: window.pid)
        }

        let selectedPID = WindowTargetResolver.resolve(
            frontmost: frontmost.flatMap(applicationSnapshot),
            lastTarget: lastWindowTargetApplication.flatMap(applicationSnapshot),
            topWindows: topWindows,
            applicationsByPID: applicationsByPID.compactMapValues(applicationSnapshot),
            ownPID: pid_t(ProcessInfo.processInfo.processIdentifier),
            excludedBundleIDs: excludedWindowTargetBundleIDs
        )

        guard let selectedPID,
              let app = applicationsByPID[selectedPID] ?? NSRunningApplication(processIdentifier: selectedPID),
              isTargetApplication(app) else {
            return nil
        }

        rememberTargetApplicationIfNeeded(app)
        return app
    }

    private func focusedApplication() -> NSRunningApplication? {
        let systemWideElement = AXUIElementCreateSystemWide()
        guard let focusedApplicationElement = copyElement(systemWideElement, attribute: kAXFocusedApplicationAttribute) else {
            return nil
        }

        var pid = pid_t(0)
        guard AXUIElementGetPid(focusedApplicationElement, &pid) == .success else {
            return nil
        }

        return NSRunningApplication(processIdentifier: pid)
    }

    private var excludedWindowTargetBundleIDs: Set<String> {
        Set([
            Bundle.main.bundleIdentifier,
            "rohoswagger.gojo"
        ].compactMap { $0 })
    }

    private func rememberTargetApplicationIfNeeded(_ app: NSRunningApplication) {
        guard isTargetApplication(app) else { return }
        lastWindowTargetApplication = app
    }

    private func isTargetApplication(_ app: NSRunningApplication) -> Bool {
        WindowTargetResolver.isTargetApplication(
            applicationSnapshot(for: app),
            ownPID: pid_t(ProcessInfo.processInfo.processIdentifier),
            excludedBundleIDs: excludedWindowTargetBundleIDs
        )
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

    private func bestWindowElement(for appElement: AXUIElement, preferredWindowID: CGWindowID? = nil) -> AXUIElement? {
        let directCandidates = [
            copyElement(appElement, attribute: kAXFocusedWindowAttribute),
            copyElement(appElement, attribute: kAXMainWindowAttribute)
        ]

        for candidate in directCandidates.compactMap({ $0 }) where isUsableWindow(candidate) {
            return candidate
        }

        if let preferredWindowID,
           let matchingWindow = copyElements(appElement, attribute: kAXWindowsAttribute)?
            .first(where: { isUsableWindow($0) && windowID(of: $0) == preferredWindowID }) {
            return matchingWindow
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
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}

private extension CGRect {
    var gojoHelperScreenFlipped: CGRect {
        guard !isNull else { return self }
        let maxY = NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
        return CGRect(origin: CGPoint(x: origin.x, y: maxY - self.maxY), size: size)
    }
}
