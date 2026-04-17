//
//  KairoNotifications.swift
//  Kairo — Premium system-wide notification layer
//
//  Intercepts ALL macOS notifications and displays them
//  in Kairo's pill with app-colored glass and animations.
//

import AppKit
import SwiftUI
import UserNotifications

// ═══════════════════════════════════════════
// MARK: - Notification Model
// ═══════════════════════════════════════════

struct KairoNotif: Identifiable, Equatable {
    let id: UUID
    let appName: String
    let title: String
    let body: String
    let bundleID: String
    let appIcon: NSImage?
    let appColor: Color
    let timestamp: Date
    let hasSound: Bool

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: timestamp)
    }

    static func == (lhs: KairoNotif, rhs: KairoNotif) -> Bool { lhs.id == rhs.id }
}

// ═══════════════════════════════════════════
// MARK: - Notification Engine
// ═══════════════════════════════════════════

class KairoNotificationEngine: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = KairoNotificationEngine()

    @Published var activeNotification: KairoNotif?
    @Published var notifQueue: [KairoNotif] = []
    @Published var history: [KairoNotif] = []
    @Published var isShowingNotif = false
    @Published var unreadCount = 0

    private var iconCache: [String: NSImage] = [:]
    private var seenHashes: Set<String> = []
    private var dismissTimer: Timer?

    override init() {
        super.init()
        setupDistributedObserver()
        setupWorkspaceObserver()
    }

    // MARK: - Setup

    func requestPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .provisional]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UNUserNotificationCenter.current().delegate = self
                }
            }
        }
    }

    // UNUserNotificationCenter delegate — catches notifications TO this app
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        showInKairo(appName: content.subtitle.isEmpty ? "Kairo" : content.subtitle, title: content.title, body: content.body, bundleID: "", sound: content.sound != nil)
        completionHandler([]) // Suppress default banner
    }

    // Distributed notifications — observe specific known notification names
    func setupDistributedObserver() {
        let names = [
            "com.spotify.client.PlaybackStateChanged",
            "com.apple.Music.playerInfo",
            "com.apple.screenIsLocked",
            "com.apple.screenIsUnlocked",
        ]
        for name in names {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(onDistributed(_:)), name: NSNotification.Name(name), object: nil, suspensionBehavior: .deliverImmediately)
        }
    }

    @objc func onDistributed(_ notification: Notification) {
        let name = notification.name.rawValue
        // Filter for notification-like events
        let keywords = ["notification", "message", "alert", "received", "incoming"]
        guard keywords.contains(where: { name.lowercased().contains($0) }) else { return }
        let info = notification.userInfo
        let title = info?["title"] as? String ?? info?["summary"] as? String ?? ""
        let body = info?["body"] as? String ?? info?["text"] as? String ?? ""
        guard !title.isEmpty else { return }
        showInKairo(appName: extractAppName(from: name), title: title, body: body, bundleID: name, sound: false)
    }

    // Workspace observer — detect app launches/activations
    func setupWorkspaceObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onAppActivate(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    @objc func onAppActivate(_ notification: Notification) {
        // Could be used to reset notification state when user opens the source app
    }

    // Accessibility-based window scanning
    func startWindowScanner() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.scanForNotificationWindows()
        }
    }

    func scanForNotificationWindows() {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }

        for window in windowList {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "NotificationCenter" {
                let pid = window[kCGWindowOwnerPID as String] as? Int32 ?? 0
                guard pid > 0 else { continue }
                readNotificationFromAX(pid: pid)
            }
        }
    }

    func readNotificationFromAX(pid: Int32) {
        let app = AXUIElementCreateApplication(pid)
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children)
        guard let childArray = children as? [AXUIElement] else { return }

        for child in childArray {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            if let roleStr = role as? String, roleStr.contains("Notification") || roleStr.contains("Banner") {
                extractTextFromElement(child)
            }
        }
    }

    func extractTextFromElement(_ element: AXUIElement) {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)

        let titleStr = (title as? String) ?? (value as? String) ?? ""
        guard !titleStr.isEmpty else { return }

        var desc: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &desc)
        let bodyStr = (desc as? String) ?? ""

        showInKairo(appName: "App", title: titleStr, body: bodyStr, bundleID: "", sound: false)
    }

    // MARK: - Display

    func showInKairo(appName: String, title: String, body: String, bundleID: String, sound: Bool) {
        guard !title.isEmpty else { return }

        // Deduplicate
        let hash = "\(appName):\(title):\(body)"
        guard !seenHashes.contains(hash) else { return }
        seenHashes.insert(hash)
        if seenHashes.count > 100 { seenHashes.removeFirst() }

        let notif = KairoNotif(
            id: UUID(), appName: appName, title: title, body: body, bundleID: bundleID,
            appIcon: getAppIcon(bundleID: bundleID), appColor: getAppColor(appName: appName),
            timestamp: Date(), hasSound: sound
        )

        DispatchQueue.main.async {
            self.history.insert(notif, at: 0)
            if self.history.count > 50 { self.history.removeLast() }
            self.unreadCount += 1
            self.addToQueue(notif)
        }
    }

    func addToQueue(_ notif: KairoNotif) {
        notifQueue.append(notif)
        if !isShowingNotif { showNext() }
    }

    func showNext() {
        guard !notifQueue.isEmpty else { isShowingNotif = false; return }
        isShowingNotif = true
        let notif = notifQueue.removeFirst()
        withAnimation(.kairoSpring) { activeNotification = notif }

        // Play subtle sound
        if notif.hasSound { NSSound(named: "Tink")?.play() }

        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: notif.body.count > 50 ? 8.0 : 5.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.dismissCurrent() }
        }
    }

    func dismissCurrent() {
        withAnimation(.kairoSpring) { activeNotification = nil; isShowingNotif = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showNext() }
    }

    func clearAll() {
        notifQueue.removeAll()
        withAnimation(.kairoFast) { activeNotification = nil; isShowingNotif = false; unreadCount = 0 }
    }

    func markRead() { unreadCount = 0 }

    // MARK: - Helpers

    func getAppIcon(bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        guard !bundleID.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[bundleID] = icon
        return icon
    }

    func getAppColor(appName: String) -> Color {
        let n = appName.lowercased()
        if n.contains("telegram") { return Color(hex: 0x2AABEE) }
        if n.contains("whatsapp") { return Color(hex: 0x25D366) }
        if n.contains("mail") || n.contains("gmail") { return Color(hex: 0xEA4335) }
        if n.contains("slack") { return Color(hex: 0x4A154B) }
        if n.contains("spotify") { return K.spotify }
        if n.contains("calendar") { return Color(hex: 0xFF3B30) }
        if n.contains("messages") { return Color(hex: 0x30D158) }
        if n.contains("twitter") || n.contains("x") { return Color(hex: 0x1DA1F2) }
        if n.contains("instagram") { return Color(hex: 0xE1306C) }
        if n.contains("zoom") { return Color(hex: 0x2D8CFF) }
        if n.contains("discord") { return Color(hex: 0x5865F2) }
        if n.contains("notion") { return .white }
        return K.cyan
    }

    func extractAppName(from identifier: String) -> String {
        let parts = identifier.components(separatedBy: ".")
        return parts.last?.capitalized ?? "App"
    }
}

// ═══════════════════════════════════════════
// MARK: - Notification Display View
// ═══════════════════════════════════════════

struct KairoNotifDisplay: View {
    let notif: KairoNotif
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // App icon with glow
            ZStack {
                Circle().fill(notif.appColor.opacity(0.3)).frame(width: 48, height: 48).blur(radius: 10)
                if let icon = notif.appIcon {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 9)).shadow(color: notif.appColor.opacity(0.4), radius: 8)
                } else {
                    Circle().fill(LinearGradient(colors: [notif.appColor, notif.appColor.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                        .overlay(Text(String(notif.appName.prefix(1))).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white))
                }
            }.frame(width: 44)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(notif.appName.uppercased()).font(.system(size: 9, design: .monospaced)).foregroundColor(notif.appColor).tracking(1.5)
                    Spacer()
                    Text(notif.timeString).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                }
                Text(notif.title).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(.white).lineLimit(1)
                if !notif.body.isEmpty {
                    Text(notif.body).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
                }
            }

            if isHovered {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(.secondary)
                }.buttonStyle(.plain).transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20).glassEffect(.regular)
                HStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(LinearGradient(colors: [notif.appColor.opacity(0.15), .clear], startPoint: .leading, endPoint: .center))
                        .frame(width: 160)
                    Spacer()
                }
                RoundedRectangle(cornerRadius: 20)
                    .stroke(LinearGradient(colors: [notif.appColor.opacity(isHovered ? 0.4 : 0.2), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
        )
        .shadow(color: notif.appColor.opacity(0.15), radius: 20, y: 8)
        .shadow(color: .black.opacity(0.4), radius: 15, y: 5)
        .offset(y: dragOffset)
        .scaleEffect(appeared ? (isHovered ? 1.01 : 1.0) : 0.85, anchor: .top)
        .opacity(appeared ? 1 : 0).blur(radius: appeared ? 0 : 8)
        .gesture(
            DragGesture()
                .onChanged { v in if v.translation.height < 0 { dragOffset = v.translation.height } }
                .onEnded { v in
                    if v.translation.height < -40 { onDismiss() }
                    else { withAnimation(.kairoSpring) { dragOffset = 0 } }
                }
        )
        .onHover { h in withAnimation(.kairoFast) { isHovered = h } }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { appeared = true } }
        .animation(.kairoFast, value: isHovered)
    }
}

// ═══════════════════════════════════════════
// MARK: - Notification History Tab
// ═══════════════════════════════════════════

struct NotificationHistoryTab: View {
    @ObservedObject var engine = KairoNotificationEngine.shared
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            if engine.history.isEmpty {
                emptyState
            } else {
                header
                notificationList
            }
        }
        .onAppear {
            engine.markRead()
            withAnimation(.kairoSpring.delay(0.1)) { appeared = true }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [K.cyan.opacity(0.06), .clear],
                            center: .center, startRadius: 0, endRadius: 40
                        )
                    )
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(.ultraThinMaterial.opacity(0.3))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle().stroke(
                            LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 0.5
                        )
                    )
                Image(systemName: "bell.slash")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(
                        LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                    )
            }
            VStack(spacing: 5) {
                Text("All Clear")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Text("Notifications will appear here")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.kTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                Circle()
                    .fill(K.cyan)
                    .frame(width: 5, height: 5)
                    .shadow(color: K.cyan.opacity(0.5), radius: 3)
                Text("\(engine.history.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("NOTIFICATIONS")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.kTextTertiary)
                    .tracking(1.5)
            }
            Spacer()
            Button(action: {
                withAnimation(.kairoFast) { engine.history.removeAll(); engine.unreadCount = 0 }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle").font(.system(size: 9, weight: .medium))
                    Text("Clear")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .foregroundColor(.kTextTertiary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    Capsule().fill(.white.opacity(0.04))
                        .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
                )
            }
            .buttonStyle(KairoBounce())
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var notificationList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 6) {
                ForEach(Array(engine.history.enumerated()), id: \.element.id) { i, notif in
                    NotificationHistoryRow(notif: notif, index: i)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.98))
                        ))
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 10)
        }
    }
}

struct NotificationHistoryRow: View {
    let notif: KairoNotif
    let index: Int
    @State private var appeared = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if let icon = notif.appIcon {
                    Image(nsImage: icon).resizable().scaledToFit()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: notif.appColor.opacity(isHovered ? 0.4 : 0.15), radius: isHovered ? 8 : 4)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(colors: [notif.appColor.opacity(0.3), notif.appColor.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 30, height: 30)
                        .overlay(
                            Text(String(notif.appName.prefix(1)))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(notif.appColor)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(notif.appName.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(notif.appColor)
                        .tracking(0.8)
                    Spacer()
                    Text(notif.timeString)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.kTextMuted)
                }
                Text(notif.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !notif.body.isEmpty {
                    Text(notif.body)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundColor(.kTextSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(11)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(.ultraThinMaterial.opacity(0.3))
                RoundedRectangle(cornerRadius: 13)
                    .fill(
                        LinearGradient(
                            colors: [notif.appColor.opacity(isHovered ? 0.06 : 0.02), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                RoundedRectangle(cornerRadius: 13)
                    .stroke(
                        LinearGradient(
                            colors: [notif.appColor.opacity(isHovered ? 0.2 : 0.08), .white.opacity(0.04)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            withAnimation(.kairoSpring.delay(Double(min(index, 8)) * 0.03)) { appeared = true }
        }
        .onHover { h in withAnimation(.kairoFast) { isHovered = h } }
    }
}
