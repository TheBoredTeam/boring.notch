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

    private var appElement: AXUIElement?
    private var pollTimer: DispatchSourceTimer?
    private var live: [String: AXUIElement] = [:]

    /// Banners being deliberately kept alive so their reply field stays
    /// usable, and of those, the ones moved off-screen.
    private var held: Set<String> = []
    private var heldOffScreen: Set<String> = []
    private var lastRefresh = Date.distantPast

    /// Comfortably inside the ~5s dismissal window the toggle resets, so a
    /// missed tick can't let a held banner slip away.
    private let refreshInterval: TimeInterval = 2.5

    /// Banners live ~5s, so 0.35s catches every one with room to spare.
    /// (An adaptive cadence with a 2s idle tick was tried and regressed
    /// UX: mirrored peeks felt delayed-to-ignored. Latency beats idle power
    /// here — notification mirroring is opt-in.)
    private let pollInterval: TimeInterval = 0.35

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

        // Polling only, deliberately — no AXObserver and no Timer.
        //
        // This runs inside an XPC service, whose main thread is driven by
        // dispatch_main(). That services DispatchQueue.main blocks but does
        // NOT run a CFRunLoop, so anything depending on one is dead code
        // here: Timer/RunLoop.add never fires, and an AXObserver's
        // CFRunLoopSource never delivers. An earlier version used both and
        // silently captured nothing after the single scan() below — the
        // watcher reported "started" and then went quiet forever.
        //
        // A DispatchSourceTimer needs no run loop, so it works. All watcher
        // state stays on the main queue, which is also where the helper
        // dispatches reply/action calls, so there's no locking to get wrong.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in self?.scan() }
        timer.resume()
        pollTimer = timer

        scan()
        return true
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        appElement = nil
        live.removeAll()
        // Correctness hygiene rather than the fix for a live leak: once
        // pollTimer stops, refreshHeldBanners never runs again either, so
        // anything still in `held` stops being artificially kept alive and
        // dies on its own within a couple of seconds regardless. But
        // leaving stale tokens around after a stop/restart cycle is still
        // wrong, so clear them explicitly.
        held.removeAll()
        heldOffScreen.removeAll()
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
            heldOffScreen.remove(token)
            onBannerGone?(token)
        }

        refreshHeldBanners()
    }

    /// Keeps held banners from timing out.
    ///
    /// Measured: an untouched banner dies in ~1.25s and its AX element is
    /// destroyed with it, which is what made replying impossible after the
    /// fact. Performing the details toggle resets that dismissal timer —
    /// re-performing it on an interval held a banner alive for a full 30s
    /// test with its reply field intact. That's what lets the notch offer a
    /// working reply box for as long as the notification is showing.
    private func refreshHeldBanners() {
        guard !held.isEmpty else { return }
        let now = Date()
        guard now.timeIntervalSince(lastRefresh) >= refreshInterval else { return }
        lastRefresh = now

        for token in held {
            guard let banner = live[token] else { continue }
            if let toggle = rawAction(on: banner, matching: { $0.localizedCaseInsensitiveContains("details") }) {
                AXUIElementPerformAction(banner, toggle as CFString)
            }
        }
    }

    /// Holds a banner open so its reply field stays usable, moving it
    /// off-screen first.
    ///
    /// The move is not optional. Holding a banner works by re-performing
    /// its details toggle, which leaves it expanded — showing its own reply
    /// field, on top of everything, taking focus. Two live text fields
    /// competing for the same keystrokes is worse than no keep-alive at
    /// all, so the banner is parked off-screen for the whole hold and the
    /// notch is the only visible surface.
    ///
    /// Safe to leave behind: with no banners showing, notificationcenterui
    /// has zero windows — the window is created per session and destroyed
    /// after — so a moved window can't permanently hide notifications. A
    /// fresh one always spawns at its normal position.
    func hold(token: String) {
        guard let banner = live[token] else { return }
        held.insert(token)

        guard !heldOffScreen.contains(token) else { return }
        heldOffScreen.insert(token)
        guard let windowValue = banner[kAXWindowAttribute],
              CFGetTypeID(windowValue as CFTypeRef) == AXUIElementGetTypeID() else { return }
        let window = windowValue as! AXUIElement
        var target = CGPoint(x: -5000, y: -5000)
        if let position = AXValueCreate(.cgPoint, &target) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
    }

    /// Stops holding a banner and lets it dismiss naturally.
    func release(token: String) {
        held.remove(token)
        heldOffScreen.remove(token)
        guard let banner = live[token] else { return }
        if let close = rawAction(on: banner, matching: { $0.localizedCaseInsensitiveContains("close") }) {
            AXUIElementPerformAction(banner, close as CFString)
        }
    }

    /// Measured, not assumed: once a banner leaves the screen its
    /// AXUIElement is destroyed outright — reading AXRole from a retained
    /// reference returns nil and AXUIElementCopyActionNames returns empty.
    /// Holding onto elements past their banner therefore buys nothing, so
    /// this is just `live`. Replying is only possible while the banner is
    /// on screen; there is no API to send on an app's behalf afterwards.
    private func element(for token: String) -> AXUIElement? {
        live[token]
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

    /// Matches on a normalized name because both sides can carry invisible
    /// bidi marks: WhatsApp's `localizedName` is literally "\u{200E}WhatsApp"
    /// (LEFT-TO-RIGHT MARK), and the banner's own description is wrapped in
    /// isolates. Comparing raw strings silently failed to resolve WhatsApp's
    /// bundle ID, which dropped every one of its notifications at the
    /// allow-list check.
    private func bundleID(forAppNamed name: String) -> String? {
        let target = Self.normalizedAppName(name)
        guard !target.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            guard let localizedName = $0.localizedName else { return false }
            return Self.normalizedAppName(localizedName) == target
        }?.bundleIdentifier
    }

    private static func normalizedAppName(_ name: String) -> String {
        name.filter { !$0.unicodeScalars.allSatisfy(bidiControlCharacters.contains) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Directional formatting characters Notification Center and app names
    /// both sprinkle in: LRM/RLM, the isolate family, and the embedding /
    /// override set.
    private static let bidiControlCharacters: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "\u{200E}\u{200F}")           // LRM, RLM
        set.insert(charactersIn: "\u{2066}"..."\u{2069}")      // isolates + PDI
        set.insert(charactersIn: "\u{202A}"..."\u{202E}")      // embeddings/overrides
        return set
    }()

    // MARK: - Acting on a banner

    /// Types into the banner's reply field and submits it. Only works while
    /// the banner is on screen and the source app offers a reply field; the
    /// caller falls back to opening the app otherwise.
    ///
    /// Verified against a live WhatsApp banner (2026-08-12): a collapsed
    /// banner's actions are ["AXPress", "Show Details", "Reply", "Close"] —
    /// a real "Reply" action does exist (an earlier check only ever caught
    /// the banner post-expansion, where it's already gone, which led to a
    /// wrong assumption here). "Reply" is preferred since it's the more
    /// direct, purpose-built action; "Show Details" is the fallback for
    /// banners/apps that don't expose it. Either way the field is submitted
    /// via the "Send" action on the banner — not kAXConfirmAction on the
    /// field, which is untested and unreliable across text-area
    /// implementations.
    func reply(token: String, text: String) -> Bool {
        guard let banner = element(for: token) else { return false }

        if replyField(in: banner) == nil {
            if let action = rawAction(on: banner, matching: { $0.localizedCaseInsensitiveContains("reply") })
                ?? rawAction(on: banner, matching: { $0.localizedCaseInsensitiveContains("details") }) {
                AXUIElementPerformAction(banner, action as CFString)
            } else if let button = descendants(of: banner, matching: [kAXButtonRole]).first(where: {
                ($0[kAXTitleAttribute] as? String)?.lowercased().contains("reply") == true
            }) {
                AXUIElementPerformAction(button, kAXPressAction as CFString)
            }
            // Thread.sleep, not RunLoop.run: there's no CFRunLoop to advance
            // in an XPC service, so RunLoop.run(until:) returns immediately
            // and the reply field wouldn't have appeared yet.
            Thread.sleep(forTimeInterval: 0.4)
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
        guard let banner = element(for: token) else { return false }
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
        guard let banner = element(for: token) else { return false }
        return AXUIElementPerformAction(banner, kAXPressAction as CFString) == .success
    }

    /// Clears the banner from screen. Notification Center exposes this as a
    /// "Close" action rather than the AXRemove one might expect.
    func dismiss(token: String) -> Bool {
        guard let banner = element(for: token),
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
