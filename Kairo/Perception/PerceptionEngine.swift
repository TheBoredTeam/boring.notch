import Foundation
import AppKit
import ApplicationServices

/// macOS Perception Engine.
///
/// Walks the accessibility tree of the focused application using
/// `AXUIElement` / `ApplicationServices`, returning a compact
/// `PerceptionContext` for the Agent Core.
///
/// Apple's macOS Accessibility API is the same `AXUIElement` family the
/// brief describes for iOS — same name, different framework
/// (`ApplicationServices` on Mac vs `UIKit` on iOS).
///
/// Requires the user to have granted Accessibility permission for Kairo
/// in System Settings → Privacy & Security → Accessibility. If permission
/// is missing, `perceive()` returns a context with `screenSummary`
/// explaining what to do.
@MainActor
final class KairoPerceptionEngine {
    static let shared = KairoPerceptionEngine()

    /// Cap the number of UI elements returned so the LLM context stays sane.
    /// Walking deeper trees beyond this is supported via filtering tools.
    private let maxElements: Int = 40

    /// Cap how deep we'll descend into a window's AX tree.
    private let maxDepth: Int = 8

    private init() {}

    // MARK: - Public

    /// Returns the user's current screen context as a `PerceptionContext`.
    /// `query` (optional) filters the UI element list — only elements whose
    /// title/value contain the query are kept after walking the tree.
    func perceive(query: String? = nil) -> PerceptionContext {
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "Unknown"
        let bundleID = app?.bundleIdentifier
        let pid = app?.processIdentifier

        guard isAccessibilityTrusted() else {
            return PerceptionContext(
                activeAppName: appName,
                activeAppBundleID: bundleID,
                activeWindowTitle: nil,
                screenSummary: "Accessibility permission not granted. Grant in System Settings → Privacy & Security → Accessibility, then add Kairo.",
                relevantUIElements: [],
                screenshotPath: nil,
                timestamp: Date()
            )
        }

        guard let pid else {
            return PerceptionContext(
                activeAppName: appName,
                activeAppBundleID: bundleID,
                activeWindowTitle: nil,
                screenSummary: "No frontmost app.",
                relevantUIElements: [],
                screenshotPath: nil,
                timestamp: Date()
            )
        }

        let appAX = AXUIElementCreateApplication(pid)
        let windowTitle = focusedWindowTitle(of: appAX)
        var elements: [UIElementDescription] = []
        if let focusedWindow = focusedWindow(of: appAX) {
            walk(focusedWindow, path: "0", depth: 0, into: &elements)
        }

        // Filter by query
        if let q = query?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            let lower = q.lowercased()
            elements = elements.filter { el in
                (el.title?.lowercased().contains(lower) ?? false)
                || (el.value?.lowercased().contains(lower) ?? false)
                || el.role.lowercased().contains(lower)
            }
        }

        // Cap
        if elements.count > maxElements {
            elements = Array(elements.prefix(maxElements))
        }

        let summary = buildSummary(appName: appName, windowTitle: windowTitle, elements: elements)
        return PerceptionContext(
            activeAppName: appName,
            activeAppBundleID: bundleID,
            activeWindowTitle: windowTitle,
            screenSummary: summary,
            relevantUIElements: elements,
            screenshotPath: nil,
            timestamp: Date()
        )
    }

    /// Cheap permission check that does NOT prompt. To prompt for permission,
    /// the user must run the app once with an AX call that needs trust;
    /// macOS surfaces the prompt automatically.
    func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Triggers the macOS Accessibility-permission prompt if not yet trusted.
    /// Returns whether trust was granted *as of this call* (may still need a
    /// follow-up call after the user grants).
    @discardableResult
    func requestAccessibilityTrust() -> Bool {
        let opts: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true
        ]
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Walk

    private func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref)
        guard result == .success, let val = ref else { return nil }
        return (val as! AXUIElement)
    }

    private func focusedWindowTitle(of app: AXUIElement) -> String? {
        guard let window = focusedWindow(of: app) else { return nil }
        return stringAttribute(window, kAXTitleAttribute)
    }

    private func walk(_ element: AXUIElement, path: String, depth: Int, into list: inout [UIElementDescription]) {
        guard depth <= maxDepth, list.count < maxElements else { return }

        let role = stringAttribute(element, kAXRoleAttribute) ?? "AXUnknown"
        let title = stringAttribute(element, kAXTitleAttribute)
        let value = stringAttribute(element, kAXValueAttribute)
            ?? stringAttribute(element, kAXDescriptionAttribute)
        let frame = frame(of: element) ?? .zero
        let interactable = isInteractable(role: role, element: element)

        // Skip pure "AXGroup" / "AXSplitGroup" / "AXLayoutArea" containers
        // that have no useful text — they're just plumbing.
        let containerRoles: Set<String> = ["AXGroup", "AXSplitGroup", "AXLayoutArea", "AXScrollArea", "AXLayoutItem"]
        let isJustContainer = containerRoles.contains(role) && (title?.isEmpty != false) && (value?.isEmpty != false)

        // Children
        let children = childrenArray(of: element)

        if !isJustContainer {
            let descr = UIElementDescription(
                id: path,
                role: role,
                title: title,
                value: value,
                frame: frame,
                isInteractable: interactable,
                children: children.count
            )
            list.append(descr)
        }

        // Recurse
        for (i, child) in children.enumerated() where list.count < maxElements {
            walk(child, path: "\(path).\(i)", depth: depth + 1, into: &list)
        }
    }

    private func childrenArray(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref)
        guard result == .success, let val = ref as? [AXUIElement] else { return [] }
        return val
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard result == .success, let val = ref else { return nil }
        if let s = val as? String, !s.isEmpty { return s }
        // Numeric / other → string
        return String(describing: val)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        let r1 = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        let r2 = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        guard r1 == .success, r2 == .success,
              let pv = positionRef, let sv = sizeRef else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &p)
        AXValueGetValue(sv as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private func isInteractable(role: String, element: AXUIElement) -> Bool {
        // Roles that almost always accept user actions
        let alwaysInteractable: Set<String> = [
            "AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton",
            "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXSlider",
            "AXLink", "AXMenuItem", "AXMenuBarItem", "AXCell"
        ]
        if alwaysInteractable.contains(role) { return true }

        // Otherwise: does the element advertise any AX actions?
        var actions: CFArray?
        let result = AXUIElementCopyActionNames(element, &actions)
        if result == .success, let actions = actions as? [String], !actions.isEmpty {
            return true
        }
        return false
    }

    // MARK: - Summary

    /// Builds a short summary for the LLM. The full element list is also
    /// included in the context so the model can drill in if needed.
    private func buildSummary(appName: String, windowTitle: String?, elements: [UIElementDescription]) -> String {
        var parts: [String] = ["App: \(appName)"]
        if let windowTitle, !windowTitle.isEmpty { parts.append("Window: \"\(windowTitle)\"") }

        let texts = elements
            .prefix(8)
            .compactMap { el -> String? in
                let body = el.title ?? el.value ?? ""
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed.prefix(80).description
            }
        if !texts.isEmpty {
            parts.append("Visible: " + texts.joined(separator: " · "))
        }

        let interactCount = elements.filter { $0.isInteractable }.count
        if interactCount > 0 {
            parts.append("\(interactCount) interactive element\(interactCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " — ")
    }
}
