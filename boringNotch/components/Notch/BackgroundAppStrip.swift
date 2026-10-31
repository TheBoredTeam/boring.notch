//
//  BackgroundAppStrip.swift
//  boringNotch
//
//  Horizontal strip of background app icons shown in the expanded notch header
//

import Defaults
import SwiftUI

struct BackgroundAppStrip: View {
    @ObservedObject var appsManager = BackgroundAppsManager.shared
    @State private var hasAppeared = false
    @State private var haptics: Bool = false

    var body: some View {
        Group {
            if appsManager.runningApps.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(appsManager.runningApps.enumerated()), id: \.element.id) { index, app in
                            AppIconNSView(app: app, onTap: {
                                if Defaults[.enableHaptics] { haptics.toggle() }
                            })
                            .frame(width: 22, height: 22)
                            .opacity(hasAppeared ? 1 : 0)
                            .scaleEffect(hasAppeared ? 1 : 0.5)
                            .animation(
                                .spring(response: 0.35, dampingFraction: 0.7)
                                    .delay(Double(index) * 0.03),
                                value: hasAppeared
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .sensoryFeedback(.alignment, trigger: haptics)
                .onAppear {
                    hasAppeared = false
                    withAnimation {
                        hasAppeared = true
                    }
                }
                .onChange(of: appsManager.runningApps.count) { _, newCount in
                    if newCount > 0 {
                        hasAppeared = false
                        withAnimation {
                            hasAppeared = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Native AppKit view with right-click menu

struct AppIconNSView: NSViewRepresentable {
    let app: AppInfo
    var onTap: (() -> Void)?

    func makeNSView(context: Context) -> AppIconView {
        let view = AppIconView(app: app, onTap: onTap)
        view.toolTip = app.localizedName
        return view
    }

    func updateNSView(_ nsView: AppIconView, context: Context) {
        nsView.updateIcon(app.icon)
        nsView.onTap = onTap
        nsView.toolTip = app.localizedName
    }
}

final class AppIconView: NSView {
    private let app: AppInfo
    private let imageView: NSImageView
    private var trackingArea: NSTrackingArea?
    var onTap: (() -> Void)?

    init(app: AppInfo, onTap: (() -> Void)? = nil) {
        self.app = app
        self.onTap = onTap
        self.imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        updateIcon(app.icon)
        addSubview(imageView)
        self.updateTrackingAreas()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateIcon(_ icon: NSImage) {
        let sized = icon.copy() as! NSImage
        sized.size = NSSize(width: 22, height: 22)
        imageView.image = sized
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        if let ta = trackingArea { addTrackingArea(ta) }
    }

    override func mouseEntered(with event: NSEvent) {
        imageView.frame = NSRect(x: -2, y: -2, width: 26, height: 26)
    }

    override func mouseExited(with event: NSEvent) {
        imageView.frame = NSRect(x: 0, y: 0, width: 22, height: 22)
    }

    override func mouseDown(with event: NSEvent) {
        BackgroundAppsManager.shared.activateApp(app)
        onTap?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        // Title item: app name
        let titleItem = NSMenuItem(title: app.localizedName, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        titleItem.image = app.icon
        titleItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(titleItem)
        menu.addItem(.separator())

        // Show
        let showItem = NSMenuItem(title: "Show", action: #selector(menuShow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Force Quit
        let forceItem = NSMenuItem(title: "Force Quit", action: #selector(menuForceQuit), keyEquivalent: "")
        forceItem.keyEquivalentModifierMask = [.command, .option]
        forceItem.target = self
        menu.addItem(forceItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - Menu actions

    @objc private func menuShow() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        }
    }

    @objc private func menuQuit() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        apps.first?.terminate()
    }

    @objc private func menuForceQuit() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        apps.first?.forceTerminate()
    }
}
