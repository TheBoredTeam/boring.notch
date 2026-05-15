import Foundation
import AppKit

// Monitors macOS Notification Center via accessibility API.
// Fragile across macOS updates — Apple may change NC's AX hierarchy.
@MainActor
final class NotificationMonitor {
    static let shared = NotificationMonitor()

    private var observer: AXObserver?
    private var seenNotifications = Set<String>()

    func start() {
        guard requestAccessibility() else {
            print("[Kairo] Accessibility permission required for notification monitor")
            return
        }

        guard let nc = NSRunningApplication.runningApplications(withBundleIdentifier:
            "com.apple.notificationcenterui").first else {
            print("[Kairo] NotificationCenter process not found")
            return
        }

        let app = AXUIElementCreateApplication(nc.processIdentifier)

        var obs: AXObserver?
        let result = AXObserverCreate(nc.processIdentifier, { _, element, notification, refcon in
            guard let refcon else { return }
            let monitor = Unmanaged<NotificationMonitor>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                monitor.handleUIChange(element: element)
            }
        }, &obs)

        guard result == .success, let obs else {
            print("[Kairo] Failed to create AXObserver")
            return
        }

        self.observer = obs
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(obs, app, kAXCreatedNotification as CFString, refcon)
        AXObserverAddNotification(obs, app, kAXWindowCreatedNotification as CFString, refcon)

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )

        print("[Kairo] Notification monitor started")
    }

    private func handleUIChange(element: AXUIElement) {
        var title: AnyObject?
        var description: AnyObject?

        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)

        let titleStr = (title as? String) ?? ""
        let bodyStr = (description as? String) ?? ""

        var children: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        let childElements = (children as? [AXUIElement]) ?? []

        var appName = "System"
        var bodyText = bodyStr
        for child in childElements {
            var value: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &value)
            if let str = value as? String, !str.isEmpty {
                if appName == "System" { appName = str }
                else if bodyText.isEmpty { bodyText = str }
            }
        }

        guard !titleStr.isEmpty || !bodyText.isEmpty else { return }

        let key = "\(appName)|\(titleStr)|\(bodyText)"
        guard !seenNotifications.contains(key) else { return }
        seenNotifications.insert(key)

        if seenNotifications.count > 500 { seenNotifications.removeAll() }

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"

        let notif = NotificationData(
            app: appName,
            title: titleStr.isEmpty ? appName : titleStr,
            body: bodyText,
            icon: iconFor(app: appName),
            timestamp: timeFmt.string(from: Date())
        )

        NotificationCenter.default.post(
            name: .kairoIncomingNotification,
            object: notif
        )
    }

    private func iconFor(app: String) -> String {
        let lower = app.lowercased()
        if lower.contains("slack")    { return "💬" }
        if lower.contains("mail")     { return "✉️" }
        if lower.contains("calendar") { return "📅" }
        if lower.contains("message")  { return "💬" }
        if lower.contains("reminder") { return "🔔" }
        if lower.contains("safari")   { return "🧭" }
        if lower.contains("chrome")   { return "🌐" }
        if lower.contains("whatsapp") { return "💚" }
        if lower.contains("discord")  { return "🎮" }
        if lower.contains("xcode")    { return "🛠️" }
        return "🔔"
    }

    private func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
