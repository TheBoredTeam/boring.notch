//
//  NotificationWatcher.swift
//  BoringNotchXPCHelper
//
//  Observes Notification Center banners through the Accessibility API and
//  streams them to the app. This lives in the helper because the app itself is
//  sandboxed, and a sandboxed process cannot drive AX on another application.
//
//  Verified hierarchy (macOS 26):
//    AXWindow "Notification Center" (subrole AXSystemDialog)
//      └ … groups … > AXScrollArea (identifier AXNotificationListItems)
//          └ banner (subrole AXNotificationCenterBanner)
//              · AXIdentifier            = per-notification UUID
//              · AXAttributedDescription = "App, Title, Subtitle, Body"
//              └ AXStaticText identifier "title" / "subtitle" / "body" (AXValue)
//
//  The window only exists while banners are on screen, so a banner is only
//  actionable while visible.
//

import Foundation
import ApplicationServices
import AppKit

private let notificationCenterBundleID = "com.apple.notificationcenterui"
private let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]

struct CapturedNotification {
    let token: String       // banner AXIdentifier (UUID), stable while on screen
    let appName: String?
    let bundleID: String?
    let title: String?
    let subtitle: String?
    let body: String?
    let actions: [String]   // AX action names, e.g. AXPress / AXReply / button titles
}

final class NotificationWatcher {
    var onBanner: ((CapturedNotification) -> Void)?
    var onBannerGone: ((String) -> Void)?

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var pollTimer: Timer?
    private var live: [String: AXUIElement] = [:]

    var isRunning: Bool { appElement != nil }

    // MARK: - Lifecycle

    @discardableResult
    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard !isRunning else { return true }
        guard let notificationCenter = NSRunningApplication.runningApplications(
            withBundleIdentifier: notificationCenterBundleID
        ).first else { return false }

        let app = AXUIElementCreateApplication(notificationCenter.processIdentifier)
        appElement = app

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            Unmanaged<NotificationWatcher>.fromOpaque(context).takeUnretainedValue().scan()
        }
        if AXObserverCreate(notificationCenter.processIdentifier, callback, &created) == .success,
           let created {
            let context = Unmanaged.passUnretained(self).toOpaque()
            for name in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXUIElementDestroyedNotification] {
                AXObserverAddNotification(created, app, name as CFString, context)
            }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .defaultMode)
            observer = created
        }

        // ponytail: the AX notifications above fire inconsistently for the
        // banner window, so a light poll backstops them. Remove the timer if a
        // single notification name ever proves reliable across releases.
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.current.add(timer, forMode: .common)
        pollTimer = timer

        scan()
        return true
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        appElement = nil
        live.removeAll()
    }

    // MARK: - Scanning

    private func scan() {
        guard let appElement else { return }
        var seen: Set<String> = []

        for window in (appElement[kAXWindowsAttribute] as? [AXUIElement]) ?? [] {
            guard window[kAXSubroleAttribute] as? String == "AXSystemDialog" else { continue }
            for banner in banners(in: window) {
                guard let token = banner[kAXIdentifierAttribute] as? String else { continue }
                seen.insert(token)
                guard live[token] == nil else { continue }
                live[token] = banner
                onBanner?(capture(banner, token: token))
            }
        }

        for token in live.keys where !seen.contains(token) {
            live[token] = nil
            onBannerGone?(token)
        }
    }

    /// Match on subrole rather than a fixed containment path — the wrapping
    /// groups change between macOS releases, the subrole has not.
    private func banners(in element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 14 else { return [] }
        if let subrole = element[kAXSubroleAttribute] as? String, bannerSubroles.contains(subrole) {
            return [element]
        }
        return ((element[kAXChildrenAttribute] as? [AXUIElement]) ?? [])
            .flatMap { banners(in: $0, depth: depth + 1) }
    }

    // MARK: - Reading a banner

    private func capture(_ banner: AXUIElement, token: String) -> CapturedNotification {
        var parts: [String: String] = [:]
        collectLabelledText(in: banner, into: &parts)

        // AXAttributedDescription reads "App, Title, Subtitle, Body"; only its
        // first field (the app name) isn't available as a labelled child.
        let appName = (banner["AXAttributedDescription"] as? NSAttributedString)?.string
            .components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{200E}\u{2068}\u{2069}"))

        return CapturedNotification(
            token: token,
            appName: appName,
            bundleID: appName.flatMap(bundleID(forAppNamed:)),
            title: parts["title"],
            subtitle: parts["subtitle"],
            body: parts["body"],
            actions: availableActions(on: banner)
        )
    }

    private func collectLabelledText(in element: AXUIElement, into parts: inout [String: String], depth: Int = 0) {
        guard depth < 10 else { return }
        if let identifier = element[kAXIdentifierAttribute] as? String,
           ["title", "subtitle", "body"].contains(identifier),
           let value = element[kAXValueAttribute] as? String {
            parts[identifier] = value.trimmingCharacters(
                in: CharacterSet(charactersIn: "\u{2068}\u{2069}\u{200E}").union(.whitespacesAndNewlines)
            )
        }
        for child in (element[kAXChildrenAttribute] as? [AXUIElement]) ?? [] {
            collectLabelledText(in: child, into: &parts, depth: depth + 1)
        }
    }

    /// Reply/Accept/Decline are exposed either as AX actions on the banner or
    /// as descendant buttons, and which one varies by app and notification
    /// type — so report both rather than guessing.
    private func availableActions(on banner: AXUIElement) -> [String] {
        // AXPress is the "open the notification" default, not a user-facing
        // choice — the notch exposes that as tapping the notification itself.
        var labels = actionNames(of: banner)
            .map(actionLabel)
            .filter { $0 != kAXPressAction }
        for button in descendants(of: banner, matching: [kAXButtonRole, kAXMenuButtonRole]) {
            if let title = button[kAXTitleAttribute] as? String, !title.isEmpty {
                labels.append(title)
            }
        }
        return labels
    }

    /// Maps a user-facing label back to the raw action string AX expects.
    private func rawAction(on element: AXUIElement, matching predicate: (String) -> Bool) -> String? {
        actionNames(of: element).first { predicate(actionLabel($0)) }
    }

    /// Raw action names as AX reports them. Notification Center returns records
    /// rather than plain names for its custom actions:
    ///     "Name:Reply\nTarget:0x0\nSelector:(null)"
    /// The raw string is what `AXUIElementPerformAction` needs, so keep it and
    /// use `actionLabel` for anything user-facing.
    private func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    private func actionLabel(_ raw: String) -> String {
        guard raw.hasPrefix("Name:") else { return raw }
        return String(raw.dropFirst("Name:".count).prefix { !$0.isNewline })
    }

    private func descendants(of element: AXUIElement, matching roles: [String], depth: Int = 0) -> [AXUIElement] {
        guard depth < 10 else { return [] }
        var found: [AXUIElement] = []
        if depth > 0, let role = element[kAXRoleAttribute] as? String, roles.contains(role) {
            found.append(element)
        }
        for child in (element[kAXChildrenAttribute] as? [AXUIElement]) ?? [] {
            found += descendants(of: child, matching: roles, depth: depth + 1)
        }
        return found
    }

    private func bundleID(forAppNamed name: String) -> String? {
        NSWorkspace.shared.runningApplications.first {
            $0.localizedName == name
        }?.bundleIdentifier
    }

    // MARK: - Acting on a banner

    /// Types into the banner's reply field and submits it. Only works while
    /// the banner is on screen and the source app offers a reply field; the
    /// caller falls back to opening the app otherwise.
    ///
    /// Verified against a live WhatsApp banner (2026-08-12): Notification
    /// Center does not expose a "Reply" action. The field is revealed by
    /// "Show Details" (collapsed) / "Hide Details" (already expanded), and
    /// submitted with a "Send" action on the banner itself — not
    /// kAXConfirmAction on the field, which is untested and unreliable across
    /// text-area implementations.
    func reply(token: String, text: String) -> Bool {
        guard let banner = live[token] else { return false }

        if replyField(in: banner) == nil {
            if let action = rawAction(on: banner, matching: { $0.localizedCaseInsensitiveContains("details") }) {
                AXUIElementPerformAction(banner, action as CFString)
            } else if let button = descendants(of: banner, matching: [kAXButtonRole]).first(where: {
                ($0[kAXTitleAttribute] as? String)?.lowercased().contains("reply") == true
            }) {
                AXUIElementPerformAction(button, kAXPressAction as CFString)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }

        guard let field = replyField(in: banner) else { return false }
        AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFString) == .success
        else { return false }

        if let send = rawAction(on: banner, matching: { $0.localizedCaseInsensitiveContains("send") }) {
            return AXUIElementPerformAction(banner, send as CFString) == .success
        }
        return AXUIElementPerformAction(field, kAXConfirmAction as CFString) == .success
    }

    private func replyField(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        descendants(of: element, matching: [kAXTextFieldRole, kAXTextAreaRole]).first
    }

    /// Performs a named AX action on the banner, or presses the button with
    /// that title (Accept / Decline on call notifications).
    func performAction(token: String, name: String) -> Bool {
        guard let banner = live[token] else { return false }
        if let raw = rawAction(on: banner, matching: { $0 == name }) {
            return AXUIElementPerformAction(banner, raw as CFString) == .success
        }
        guard let button = descendants(of: banner, matching: [kAXButtonRole, kAXMenuButtonRole]).first(where: {
            $0[kAXTitleAttribute] as? String == name
        }) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// Opens the notification in its source app (the banner's default action).
    func open(token: String) -> Bool {
        guard let banner = live[token] else { return false }
        return AXUIElementPerformAction(banner, kAXPressAction as CFString) == .success
    }

    /// Clears the banner from screen. Notification Center exposes this as a
    /// "Close" action rather than the AXRemove one might expect.
    func dismiss(token: String) -> Bool {
        guard let banner = live[token],
              let raw = rawAction(on: banner, matching: { $0.localizedCaseInsensitiveContains("close") })
        else { return false }
        return AXUIElementPerformAction(banner, raw as CFString) == .success
    }

    // MARK: - Debug

    /// Full attribute dump of the banner window, for the debug window.
    func debugDump() -> String {
        guard let appElement else { return "watcher not running" }
        var out = ""
        for window in (appElement[kAXWindowsAttribute] as? [AXUIElement]) ?? [] {
            guard window[kAXSubroleAttribute] as? String == "AXSystemDialog" else { continue }
            describe(window, depth: 0, into: &out)
        }
        return out.isEmpty ? "no banners on screen" : out
    }

    private func describe(_ element: AXUIElement, depth: Int, into out: inout String) {
        guard depth < 14 else { return }
        let pad = String(repeating: "  ", count: depth)
        out += "\(pad)\(element[kAXRoleAttribute] as? String ?? "?") \(element[kAXSubroleAttribute] as? String ?? "")"
        out += " actions=\(actionNames(of: element))\n"
        var names: CFArray?
        if AXUIElementCopyAttributeNames(element, &names) == .success, let names = names as? [String] {
            for name in names where name != kAXChildrenAttribute && name != kAXParentAttribute {
                guard let value = element[name] else { continue }
                out += "\(pad)  · \(name) = \(String(describing: value).prefix(200))\n"
            }
        }
        for child in (element[kAXChildrenAttribute] as? [AXUIElement]) ?? [] {
            describe(child, depth: depth + 1, into: &out)
        }
    }
}

private extension AXUIElement {
    subscript(attribute: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
