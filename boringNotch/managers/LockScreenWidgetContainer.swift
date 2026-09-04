//
//  LockScreenWidgetContainer.swift
//  boringNotch
//

import AppKit
import CoreGraphics
import Defaults
import SkyLightWindow
import SwiftUI

struct LockScreenWidgetContext {
    let screen: NSScreen

    var frame: NSRect { screen.frame }
    var visibleFrame: NSRect { screen.visibleFrame }
}

@MainActor
final class LockScreenWidgetCoordinator {
    static let shared = LockScreenWidgetCoordinator()

    private var containers: [ObjectIdentifier: LockScreenWidgetContainer] = [:]
    private(set) var isLockScreenVisible = false

    private init() {}

    func screenDidLock() {
        isLockScreenVisible = Defaults[.showOnLockScreen]
        refresh()
    }

    func screenDidUnlock() {
        isLockScreenVisible = false
        containers.values.forEach { $0.setVisible(false) }
    }

    func refresh() {
        let shouldShow = isLockScreenVisible && Defaults[.showOnLockScreen]
        containers.values.forEach { $0.setVisible(shouldShow) }
    }

    func shutdown() {
        isLockScreenVisible = false
        containers.values.forEach {
            $0.setVisible(false)
            $0.releaseWindow()
        }
        containers.removeAll()
    }

    fileprivate func register(_ container: LockScreenWidgetContainer) {
        containers[ObjectIdentifier(container)] = container
        container.setVisible(isLockScreenVisible && Defaults[.showOnLockScreen])
    }

    fileprivate func unregister(_ container: LockScreenWidgetContainer) {
        containers.removeValue(forKey: ObjectIdentifier(container))
        container.setVisible(false)
        container.releaseWindow()
    }
}

@MainActor
final class LockScreenWidgetContainer {
    typealias FrameProvider = (LockScreenWidgetContext) -> NSRect

    private let allowsInteraction: Bool
    private var targetScreenUUID: String?
    private var panel: NSPanel?
    private var isDelegatedToSkyLight = false
    private var makeContent: (() -> AnyView)?
    private var frameProvider: FrameProvider?
    private var cornerRadius: CGFloat = 24
    private var isEnabled = true
    private var isLockScreenVisible = false
    private var visibilityHandler: ((Bool) -> Void)?

    init(targetScreenUUID: String? = nil, allowsInteraction: Bool = false) {
        self.targetScreenUUID = targetScreenUUID
        self.allowsInteraction = allowsInteraction
    }

    func configure<Content: View>(
        cornerRadius: CGFloat = 24,
        frame: @escaping FrameProvider,
        onLockScreenVisibilityChange: ((Bool) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        frameProvider = frame
        visibilityHandler = onLockScreenVisibilityChange
        makeContent = { AnyView(content()) }
        LockScreenWidgetCoordinator.shared.register(self)
    }

    func setTargetScreen(_ screenUUID: String?) {
        targetScreenUUID = screenUUID
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        refresh()
    }

    func refresh() {
        LockScreenWidgetCoordinator.shared.refresh()
    }

    func dismiss() {
        LockScreenWidgetCoordinator.shared.unregister(self)
    }

    fileprivate func setVisible(_ visible: Bool) {
        if isLockScreenVisible != visible {
            isLockScreenVisible = visible
            visibilityHandler?(visible)
        }

        guard visible,
              isEnabled,
              let content = makeContent,
              let frameProvider,
              let context = displayContext()
        else {
            panel?.orderOut(nil)
            return
        }

        let frame = frameProvider(context)
        let panel = ensurePanel(frame: frame)
        let hostingView = NSHostingView(rootView: content())
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = true
        hostingView.layer?.cornerRadius = cornerRadius

        panel.setFrame(frame, display: true)
        panel.contentView = hostingView
        panel.sharingType = Defaults[.hideFromScreenRecording] ? .none : .readWrite

        if !isDelegatedToSkyLight {
            SkyLightOperator.shared.delegateWindow(panel)
            isDelegatedToSkyLight = true
        }

        panel.orderFrontRegardless()
    }

    fileprivate func releaseWindow() {
        guard let panel else { return }
        panel.orderOut(nil)
        if isDelegatedToSkyLight {
            SkyLightOperator.shared.undelegateWindow(panel)
            isDelegatedToSkyLight = false
        }
        panel.close()
        self.panel = nil
    }

    private func displayContext() -> LockScreenWidgetContext? {
        let screen: NSScreen?
        if let targetScreenUUID {
            screen = NSScreen.screen(withUUID: targetScreenUUID)
        } else {
            screen = NSScreen.screen(withUUID: BoringViewCoordinator.shared.selectedScreenUUID)
                ?? NSScreen.main
                ?? NSScreen.screens.first
        }

        return screen.map(LockScreenWidgetContext.init(screen:))
    }

    private func ensurePanel(frame: NSRect) -> NSPanel {
        if let panel { return panel }

        let panel = LockScreenWidgetPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            allowsInteraction: allowsInteraction
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = allowsInteraction
        panel.ignoresMouseEvents = !allowsInteraction
        self.panel = panel
        return panel
    }
}

private final class LockScreenWidgetPanel: NSPanel {
    private let allowsInteraction: Bool

    init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool,
        allowsInteraction: Bool
    ) {
        self.allowsInteraction = allowsInteraction
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
    }

    override var canBecomeKey: Bool { allowsInteraction }
    override var canBecomeMain: Bool { false }
}
