//
//  LockScreenWidgetSupport.swift
//  boringNotch
//
//  Shared SkyLight window and display placement support for lock-screen widgets.
//

import AppKit
import CoreGraphics
import Defaults
import Foundation
import SkyLightWindow
import SwiftUI

enum LockScreenText {
    static func value(_ english: String, _ simplifiedChinese: String) -> String {
        let selectedLanguage = Defaults[.appLanguage]
        let usesChinese = selectedLanguage.rawValue.hasPrefix("zh")
            || (selectedLanguage == .system && Locale.preferredLanguages.first?.hasPrefix("zh") == true)
        return usesChinese ? simplifiedChinese : english
    }
}

struct LockScreenDisplayContext {
    let screen: NSScreen
    let frame: NSRect
}

@MainActor
final class LockScreenDisplayContextProvider {
    static let shared = LockScreenDisplayContextProvider()

    private var context: LockScreenDisplayContext?
    private var observers: [NSObjectProtocol] = []

    private init() {
        refresh()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                _ = self?.refresh()
            }
        })

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                _ = self?.refresh()
            }
        })
    }

    func snapshot() -> LockScreenDisplayContext? {
        context ?? refresh()
    }

    @discardableResult
    func refresh() -> LockScreenDisplayContext? {
        guard let screen = preferredScreen() else {
            context = nil
            return nil
        }

        let newContext = LockScreenDisplayContext(screen: screen, frame: screen.frame)
        context = newContext
        return newContext
    }

    private func preferredScreen() -> NSScreen? {
        if let builtIn = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }) {
            return builtIn
        }

        return NSScreen.main ?? NSScreen.screens.first
    }
}

@MainActor
final class LockScreenWidgetPanel {
    private var window: NSPanel?
    private var delegatedToSkyLight = false
    private let allowsInteraction: Bool

    init(allowsInteraction: Bool) {
        self.allowsInteraction = allowsInteraction
    }

    var isVisible: Bool { window?.isVisible == true }
    var frame: NSRect? { window?.frame }

    func show<Content: View>(
        _ content: Content,
        frame: NSRect,
        cornerRadius: CGFloat = 24
    ) {
        let panel = ensureWindow(frame: frame)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]

        panel.setFrame(frame, display: true)
        panel.contentView = hostingView
        panel.ignoresMouseEvents = !allowsInteraction
        panel.sharingType = Defaults[.hideFromScreenRecording] ? .none : .readWrite

        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.masksToBounds = true
            contentView.layer?.cornerRadius = cornerRadius
        }

        if !delegatedToSkyLight {
            SkyLightOperator.shared.delegateWindow(panel)
            delegatedToSkyLight = true
        }

        panel.orderFrontRegardless()
    }

    func move(to frame: NSRect) {
        window?.setFrame(frame, display: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func ensureWindow(frame: NSRect) -> NSPanel {
        if let window { return window }

        let newWindow = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newWindow.isReleasedWhenClosed = false
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        newWindow.isMovable = false
        newWindow.hasShadow = false
        newWindow.hidesOnDeactivate = false
        newWindow.acceptsMouseMovedEvents = allowsInteraction
        newWindow.ignoresMouseEvents = !allowsInteraction
        window = newWindow
        return newWindow
    }
}

struct LockScreenWidgetCard<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        let appearance = Defaults[.lockScreenWidgetAppearance]
        content
            .foregroundStyle(appearance == .dark ? .white : .black)
            .background(background(for: appearance))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        appearance == .dark ? .white.opacity(0.18) : .black.opacity(0.12),
                        lineWidth: 1
                    )
            }
            .preferredColorScheme(appearance == .dark ? .dark : .light)
    }

    @ViewBuilder
    private func background(for appearance: LockScreenWidgetAppearance) -> some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.clear)
                .glassEffect(
                    .clear.tint(appearance == .dark ? .white.opacity(0.16) : .white.opacity(0.28)),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(appearance == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.48))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

enum LockScreenWidgetLayout {
    static func media(in screen: NSRect, size: CGSize) -> NSRect {
        NSRect(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height - 100,
            width: size.width,
            height: size.height
        )
    }

    static func timer(in screen: NSRect, size: CGSize, offset: CGFloat) -> NSRect {
        let y = max(screen.minY + 100, screen.midY - 84 + clamped(offset))
        return NSRect(x: screen.midX - size.width / 2, y: y, width: size.width, height: size.height)
    }

    static func weather(in screen: NSRect, size: CGSize, offset: CGFloat) -> NSRect {
        let y = min(screen.maxY - size.height - 72, screen.midY + 76 + clamped(offset))
        return NSRect(x: screen.midX - size.width / 2, y: y, width: size.width, height: size.height)
    }

    static func reminder(
        in screen: NSRect,
        size: CGSize,
        alignment: LockScreenReminderAlignment,
        offset: CGFloat
    ) -> NSRect {
        let x: CGFloat
        switch alignment {
        case .leading: x = screen.minX + 24
        case .center: x = screen.midX - size.width / 2
        case .trailing: x = screen.maxX - size.width - 24
        }
        let y = min(screen.maxY - size.height - 40, screen.midY + 8 + clamped(offset))
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func clamped(_ offset: CGFloat) -> CGFloat {
        min(max(offset, -160), 160)
    }
}
