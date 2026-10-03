//
//  AISessionFocusService.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import ApplicationServices

struct AISessionWindowBinding: Codable, Equatable {
    let bundleID: String
    let windowTitle: String
}

@MainActor
final class AISessionFocusService: ObservableObject {
    static let shared = AISessionFocusService()

    @Published private(set) var lastTerminal: AISessionWindowBinding?
    @Published private(set) var errorMessage: String?

    private var bindings: [String: AISessionWindowBinding] = [:]
    private var activationObserver: NSObjectProtocol?
    private let storageKey = "aiSessionWindowBindings"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: AISessionWindowBinding].self, from: data) {
            bindings = saved
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in self?.capture(app) }
        }
        if let app = NSWorkspace.shared.frontmostApplication { capture(app) }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    var canBindCurrentTerminal: Bool { lastTerminal != nil }

    func hasBinding(for session: AISessionRecord) -> Bool {
        bindings[session.id] != nil || session.terminalBundleID != nil
            || session.isDesktopSession || session.cwd != nil
    }

    func hasExplicitBinding(for session: AISessionRecord) -> Bool {
        bindings[session.id] != nil || session.terminalBundleID != nil
    }

    func bindLastTerminal(to session: AISessionRecord) {
        guard let lastTerminal else { return }
        bindings[session.id] = lastTerminal
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        errorMessage = nil
    }

    @discardableResult
    func focus(_ session: AISessionRecord) -> Bool {
        errorMessage = nil
        if session.isDesktopSession,
           let threadID = session.id.split(separator: ":", maxSplits: 1).last,
           let url = URL(string: "codex://threads/\(threadID)") {
            return NSWorkspace.shared.open(url)
        }

        let binding = bindings[session.id] ?? session.terminalBundleID.map {
            AISessionWindowBinding(bundleID: $0, windowTitle: session.windowTitle ?? "")
        } ?? inferredBinding(for: session)
        guard let binding,
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == binding.bundleID
              }) else {
            errorMessage = "No bound terminal is running for this session."
            return false
        }

        guard binding.windowTitle.isEmpty || raiseWindow(
            in: app, matching: binding.windowTitle
        ) else {
            errorMessage = "The bound terminal window is no longer available."
            return false
        }
        return app.activate(options: [.activateIgnoringOtherApps])
    }

    private func capture(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
              Self.supportedTerminalBundleIDs.contains(bundleID),
              let title = focusedWindowTitle(of: app), !title.isEmpty else { return }
        lastTerminal = AISessionWindowBinding(bundleID: bundleID, windowTitle: title)
    }

    private func focusedWindowTitle(of app: NSRunningApplication) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let windowElement = window as! AXUIElement
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            windowElement, kAXTitleAttribute as CFString, &title
        ) == .success else { return nil }
        return title as? String
    }

    private func raiseWindow(in app: NSRunningApplication, matching title: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }
        for window in windows {
            var currentTitle: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window, kAXTitleAttribute as CFString, &currentTitle
            ) == .success, currentTitle as? String == title else { continue }
            return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
        }
        return false
    }

    private func inferredBinding(for session: AISessionRecord) -> AISessionWindowBinding? {
        guard AXIsProcessTrusted() else { return nil }
        let token = session.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? session.projectName
        guard token.count >= 3 else { return nil }
        var matches: [AISessionWindowBinding] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  Self.supportedTerminalBundleIDs.contains(bundleID) else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
                    == .success, let windows = value as? [AXUIElement] else { continue }
            for window in windows {
                var title: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    window, kAXTitleAttribute as CFString, &title
                ) == .success, let title = title as? String,
                      title.localizedCaseInsensitiveContains(token) else { continue }
                matches.append(AISessionWindowBinding(bundleID: bundleID, windowTitle: title))
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    nonisolated static let supportedTerminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "com.github.wez.wezterm", "net.kovidgoyal.kitty",
        "org.alacritty", "co.zeit.hyper", "org.tabby", "com.raphaelamorim.rio",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
    ]
}
