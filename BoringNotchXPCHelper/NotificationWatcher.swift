//
//  NotificationWatcher.swift
//  BoringNotchXPCHelper
//
import AppKit
import ApplicationServices
import Foundation

private let notificationCenterBundleID = "com.apple.notificationcenterui"
private let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]

private extension AXUIElement {
    subscript(attribute: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
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
    private var pollTimer: DispatchSourceTimer?
    private var liveTokens = Set<String>()
    private var allowedBundleIDs = Set<String>()
    private var mirrorAllApps = false
    private var currentPollInterval: TimeInterval = 0
    private let activePollInterval: TimeInterval = 0.75
    private let idlePollInterval: TimeInterval = 2

    var isRunning: Bool { pollTimer != nil }

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
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: activePollInterval)
        timer.setEventHandler { [weak self] in self?.scan() }
        timer.resume()
        pollTimer = timer
        currentPollInterval = activePollInterval
        scan()
        return true
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        appElement = nil
        liveTokens.removeAll()
    }

    private func scan() {
        autoreleasepool {
            guard let appElement else { return }
            var seen = Set<String>()

            for window in (appElement[kAXWindowsAttribute] as? [AXUIElement]) ?? [] {
                guard window[kAXSubroleAttribute] as? String == "AXSystemDialog" else { continue }
                for banner in banners(in: window) {
                    guard let token = banner[kAXIdentifierAttribute] as? String else { continue }
                    seen.insert(token)
                    guard !liveTokens.contains(token) else { continue }
                    let notification = capture(banner, token: token)
                    guard mirrorAllApps || isAllowed(notification) else {
                        continue
                    }
                    liveTokens.insert(token)
                    onBanner?(notification)
                }
            }
            liveTokens.formIntersection(seen)
            updatePollInterval()
        }
    }

    private func updatePollInterval() {
        let interval = liveTokens.isEmpty ? idlePollInterval : activePollInterval
        guard interval != currentPollInterval, let pollTimer else { return }
        currentPollInterval = interval
        pollTimer.schedule(deadline: .now() + interval, repeating: interval)
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
