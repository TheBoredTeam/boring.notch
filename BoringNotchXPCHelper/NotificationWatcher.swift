//
//  NotificationWatcher.swift
//  BoringNotchXPCHelper
//
import AppKit
import ApplicationServices
import Foundation

private let notificationCenterBundleID = "com.apple.notificationcenterui"
private let bannerSubroles = NotificationPanelDetection.bannerSubroles

private extension AXUIElement {
    subscript(attribute: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    func point(attribute: String) -> CGPoint? {
        guard let value = self[attribute],
              CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cgPoint
        else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }
}

struct CapturedNotification {
    let token: String
    let appName: String?
    let bundleID: String?
    let title: String?
    let subtitle: String?
    let body: String?
}

final class NotificationWatcher {
    var onBanner: ((CapturedNotification) -> Void)?

    private var appElement: AXUIElement?
    private var axObserver: AXObserver?
    private var observerRunLoop: AXObserverRunLoop?
    private var pollTimer: DispatchSourceTimer?
    private var liveTokens = Set<String>()
    private var scanPending = false
    private var allowedBundleIDs = Set<String>()
    private var mirrorAllApps = false
    private var parkedWindowByToken: [String: Int] = [:]
    private var parkedWindows: [Int: (window: AXUIElement, origin: CGPoint)] = [:]
    private let activePollInterval: TimeInterval = 0.5
    private let observerNotifications = [
        kAXWindowCreatedNotification,
        kAXCreatedNotification,
        kAXUIElementDestroyedNotification
    ]

    var isRunning: Bool { appElement != nil }

    func configureFilter(bundleIDs: Set<String>, allApps: Bool) {
        allowedBundleIDs = bundleIDs
        mirrorAllApps = allApps
    }

    @discardableResult
    func start() -> Bool {
        guard AXIsProcessTrusted(), !isRunning,
              let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: notificationCenterBundleID
              ).first else {
            return false
        }

        appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard installObserver(for: application.processIdentifier) else {
            appElement = nil
            return false
        }
        // Steady state is event-driven via the AX observer; scan() starts a timer only while banners are live.
        scan()
        return true
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        if let axObserver, let appElement {
            for notification in observerNotifications {
                AXObserverRemoveNotification(axObserver, appElement, notification as CFString)
            }
            observerRunLoop?.stop()
        }
        axObserver = nil
        observerRunLoop = nil
        appElement = nil
        liveTokens.removeAll()
        restoreAllWindows()
    }

    private func installObserver(for processIdentifier: pid_t) -> Bool {
        var observer: AXObserver?
        let result = AXObserverCreate(processIdentifier, { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<NotificationWatcher>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                watcher.requestScan()
            }
        }, &observer)
        guard result == .success, let observer, let appElement else { return false }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // map, not contains: every notification must be registered, not just the first that succeeds.
        let registered = observerNotifications.map { notification in
            AXObserverAddNotification(
                observer,
                appElement,
                notification as CFString,
                refcon
            ) == .success
        }.contains(true)
        guard registered else {
            return false
        }

        let runLoop = AXObserverRunLoop(observer: observer)
        guard runLoop.start() else { return false }
        axObserver = observer
        observerRunLoop = runLoop
        return true
    }

    private final class AXObserverRunLoop {
        private let observer: AXObserver
        private let ready = DispatchSemaphore(value: 0)
        private var thread: Thread?
        private var runLoop: CFRunLoop?

        init(observer: AXObserver) {
            self.observer = observer
        }

        func start() -> Bool {
            let thread = Thread { [weak self] in
                guard let self else { return }
                let runLoop = CFRunLoopGetCurrent()
                self.runLoop = runLoop
                CFRunLoopAddSource(
                    runLoop,
                    AXObserverGetRunLoopSource(self.observer),
                    .defaultMode
                )
                self.ready.signal()
                CFRunLoopRun()
                CFRunLoopRemoveSource(
                    runLoop,
                    AXObserverGetRunLoopSource(self.observer),
                    .defaultMode
                )
            }
            self.thread = thread
            thread.start()
            return ready.wait(timeout: .now() + 1) == .success
        }

        func stop() {
            guard let runLoop else { return }
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
            thread = nil
            self.runLoop = nil
        }
    }

    // A burst of AX callbacks collapses into one scan; the flag clears before scan() so a request
    // arriving during a scan still earns a following one.
    private func requestScan() {
        guard !scanPending else { return }
        scanPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            scanPending = false
            scan()
        }
    }

    private func scan() {
        autoreleasepool {
            guard let appElement else { return }
            var seen = Set<String>()

            for window in (appElement[kAXWindowsAttribute] as? [AXUIElement]) ?? [] {
                guard !NotificationPanelDetection.isPanelWindow(Self.panelAttributes(for: window)) else { continue }
                guard window[kAXSubroleAttribute] as? String == "AXSystemDialog" else { continue }
                for banner in banners(in: window) {
                    guard let token = banner[kAXIdentifierAttribute] as? String else { continue }
                    seen.insert(token)
                    guard !liveTokens.contains(token) else { continue }
                    let notification = capture(banner, token: token)
                    guard mirrorAllApps || isAllowed(notification) else {
                        continue
                    }
                    guard park(window, for: token) else {
                        NSLog("[boringNotch] could not hide notification banner \(token)")
                        continue
                    }
                    liveTokens.insert(token)
                    onBanner?(notification)
                }
            }
            let removed = liveTokens.subtracting(seen)
            liveTokens.formIntersection(seen)
            removed.forEach(restoreWindowIfUnused)
            syncPollTimer()
        }
    }

    // Lazy and recursive: nothing is read across the process boundary until containsPanelList descends.
    private static func panelAttributes(for element: AXUIElement) -> NotificationPanelDetection.Attributes {
        .init(
            subrole: { element[$0] as? String },
            identifier: { element[$0] as? String },
            children: {
                ((element[kAXChildrenAttribute] as? [AXUIElement]) ?? [])
                    .map(Self.panelAttributes(for:))
            }
        )
    }

    // Banner teardown is not reliably reported by a destroy notification, so poll while any banner is live.
    private func syncPollTimer() {
        if liveTokens.isEmpty {
            pollTimer?.cancel()
            pollTimer = nil
        } else if pollTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + activePollInterval, repeating: activePollInterval)
            timer.setEventHandler { [weak self] in self?.scan() }
            timer.resume()
            pollTimer = timer
        }
    }

    private func park(_ window: AXUIElement, for token: String) -> Bool {
        let key = Int(bitPattern: CFHash(window))
        if parkedWindows[key] == nil {
            guard let origin = window.point(attribute: kAXPositionAttribute) else { return false }
            parkedWindows[key] = (window, origin)
            var hidden = CGPoint(x: -10000, y: -10000)
            guard let value = AXValueCreate(.cgPoint, &hidden),
                  AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
            else {
                parkedWindows.removeValue(forKey: key)
                return false
            }
        }
        parkedWindowByToken[token] = key
        return true
    }

    private func restoreWindowIfUnused(_ token: String) {
        guard let key = parkedWindowByToken.removeValue(forKey: token),
              !parkedWindowByToken.values.contains(key),
              let parked = parkedWindows.removeValue(forKey: key)
        else { return }
        var origin = parked.origin
        if let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(parked.window, kAXPositionAttribute as CFString, value)
        }
    }

    private func restoreAllWindows() {
        for token in Array(parkedWindowByToken.keys) {
            restoreWindowIfUnused(token)
        }
        parkedWindowByToken.removeAll()
        parkedWindows.removeAll()
    }

    private func banners(in element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 14 else { return [] }
        if let subrole = element[kAXSubroleAttribute] as? String, bannerSubroles.contains(subrole) {
            return [element]
        }

        return ((element[kAXChildrenAttribute] as? [AXUIElement]) ?? [])
            .flatMap { banners(in: $0, depth: depth + 1) }
    }

    private func capture(_ banner: AXUIElement, token: String) -> CapturedNotification {
        var parts = [String: String]()
        collectText(in: banner, into: &parts)
        let appName = (banner["AXAttributedDescription"] as? NSAttributedString)?.string
            .components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return CapturedNotification(
            token: token,
            appName: appName,
            bundleID: appName.flatMap(bundleID(forAppNamed:)),
            title: parts["title"],
            subtitle: parts["subtitle"],
            body: parts["body"]
        )
    }

    private func collectText(in element: AXUIElement, into parts: inout [String: String], depth: Int = 0) {
        guard depth < 10 else { return }
        if let identifier = element[kAXIdentifierAttribute] as? String,
           ["title", "subtitle", "body"].contains(identifier),
           let value = element[kAXValueAttribute] as? String {
            parts[identifier] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for child in (element[kAXChildrenAttribute] as? [AXUIElement]) ?? [] {
            collectText(in: child, into: &parts, depth: depth + 1)
        }
    }

    private func bundleID(forAppNamed name: String) -> String? {
        NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame
        }?.bundleIdentifier
    }

    private func isAllowed(_ notification: CapturedNotification) -> Bool {
        if let bundleID = notification.bundleID {
            return allowedBundleIDs.contains(bundleID)
        }
        guard let appName = notification.appName?.lowercased(), !appName.isEmpty else {
            return false
        }
        return allowedBundleIDs.contains { bundleID in
            bundleID.split(separator: ".").last.map { appName == $0.lowercased() } ?? false
        }
    }
}
