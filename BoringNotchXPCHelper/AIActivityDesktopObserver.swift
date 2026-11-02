import AppKit
import ApplicationServices
import Foundation

/// Only inspects controls in the currently exposed window. Never activates apps,
/// changes conversations, reads response bodies, or equates missing controls with success.
final class AIActivityDesktopObserver {
    private var observations: [AIProvider: AIActivitySession] = [:]

    func snapshot(excludingClaudeCode: Bool) -> [AIActivitySession] {
        guard AXIsProcessTrusted() else { observations = [:]; return [] }
        for provider in [AIProvider.chatgpt, .claude] {
            observe(provider, excluded: provider == .claude && excludingClaudeCode)
        }
        return Array(observations.values)
    }

    func reset() { observations = [:] }

    private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private func observe(_ provider: AIProvider, excluded: Bool) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: provider.bundleIdentifier).first,
              !app.isTerminated else {
            observations.removeValue(forKey: provider)
            return
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.12)
        let windowValue = attribute(root, kAXMainWindowAttribute as CFString)
        guard !excluded, let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            invalidate(provider, reason: excluded ? "Claude Code is monitored through hooks" : "No accessible conversation window")
            return
        }
        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        guard (attribute(window, kAXMinimizedAttribute as CFString) as? Bool) != true else {
            invalidate(provider, reason: "Window is minimized; state is unconfirmed")
            return
        }
        // Use the title only as a process-local identity hash; never send or persist it.
        let title = attribute(window, kAXTitleAttribute as CFString) as? String ?? ""
        let identity = "\(app.processIdentifier):\(CFHash(window)):\(title.hashValue)"
        if observations[provider]?.sessionID != identity {
            observations[provider] = AIActivitySession(provider: provider, sessionID: identity,
                status: .unknown, source: .accessibility, reason: "Only this exposed conversation is observed")
        }
        var queue: [AXUIElement] = [window]
        var cursor = 0
        var generating = false
        var needsAttention = false
        let deadline = Date().addingTimeInterval(0.35)
        while cursor < queue.count && cursor < 600 && Date() < deadline {
            let element = queue[cursor]
            cursor += 1
            let role = attribute(element, kAXRoleAttribute as CFString) as? String ?? ""
            if role == kAXButtonRole as String {
                let labels = [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute].compactMap {
                    attribute(element, $0 as CFString) as? String
                }.joined(separator: " ").lowercased()
                generating = generating || ["stop generating", "stop response", "stop streaming", "stop-button", "stop-response-button",
                    "停止生成", "停止產生", "停止回應", "停止响应", "停止回答"].contains { labels.contains($0) }
                let enabled = attribute(element, kAXEnabledAttribute as CFString) as? Bool ?? false
                needsAttention = needsAttention || (enabled && ["allow once", "always allow", "approve once", "允許一次", "始終允許", "允许一次"].contains { labels.contains($0) })
            }
            // Text nodes can contain private prompts and responses; never inspect them.
            if role != kAXStaticTextRole as String && role != kAXTextAreaRole as String,
               let children = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(max(0, 600 - queue.count)))
            }
        }
        guard var session = observations[provider] else { return }
        let next: AIActivityStatus = needsAttention ? .needsAttention : generating ? .working : .unknown
        let reason = needsAttention ? "An approval control is visible; review it in the app"
            : generating ? "Generating in the exposed conversation"
            : session.status == .working ? "Generation ended; completion is unconfirmed"
            : "No reliable work signal in this conversation"
        if next != session.status || reason != session.reason {
            session.updatedAt = Date()
            session.status = next
            session.reason = reason
            observations[provider] = session
        }
    }

    private func invalidate(_ provider: AIProvider, reason: String) {
        guard var session = observations[provider] else { return }
        if session.status != .unknown || session.reason != reason { session.updatedAt = Date() }
        session.status = .unknown
        session.reason = reason
        observations[provider] = session
    }
}
