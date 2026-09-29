//
//  FloatingShelfController.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Defaults
import KeyboardShortcuts

/// The notch drag detector stays responsible for opening the notch itself.
@MainActor
final class FloatingShelfController {
    static let shared = FloatingShelfController()

    private var shakeDetector = PointerShakeDetector()
    private var panel: FloatingShelfPanel?
    private var isPresented = false
    private var isDragging = false
    private var isContentDragging = false
    private var pasteboardChangeCount = -1
    private var dismissTask: Task<Void, Never>?
    private var keyboardPoll: Task<Void, Never>?
    /// True once the pointer has hovered the share tile during this drag.
    private var shareDropArmed = false
    /// Hardware poll only toggles on the press, not on every sample while the keys stay down.
    private var shortcutWasHeld = false

    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?
    private let dragPasteboard = NSPasteboard(name: .drag)

    private init() {}

    func start() {
        guard mouseDownMonitor == nil else { return }
        installMonitors()
        // Create the panel before any drag so its drop registration already exists.
        _ = ensurePanel()
        migrateShowShelfShortcutIfNeeded()
        KeyboardShortcuts.onKeyDown(for: .showFloatingShelf) { [weak self] in
            Task { @MainActor in
                self?.handleShortcut()
            }
        }
    }

    func stop() {
        keyboardPoll?.cancel()
        keyboardPoll = nil
        removeMonitors()
        dismiss()
    }

    private func installMonitors() {
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseDown()
            }
        }

        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            let sample = PointerSample(point: NSEvent.mouseLocation, time: ProcessInfo.processInfo.systemUptime)
            Task { @MainActor in
                self?.handleMouseDragged(sample: sample)
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseUp()
            }
        }
    }

    private func removeMonitors() {
        for monitor in [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor] {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
    }

    private func handleMouseDown() {
        pasteboardChangeCount = dragPasteboard.changeCount
        isDragging = true
        isContentDragging = false
        shareDropArmed = false
        shakeDetector.reset()
        startKeyboardPoll()
    }

    private func handleMouseDragged(sample: PointerSample) {
        guard isDragging else { return }
        noteContentDragIfNeeded()
        noteShareHover()
        guard isContentDragging, !ShelfSelectionModel.shared.isDragging else { return }

        let shaken = shakeDetector.add(sample)
        let held = HeldModifiers.readHardware()
        // Option-Shift-Space includes Shift. While that chord is down, Shift must not reopen the shelf.
        let shortcutHeld = shortcutIsHeld(held)
        guard FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: Defaults[.boringShelf],
            floatingShelfEnabled: Defaults[.floatingShelf],
            contentDragActive: true,
            shake: shaken,
            shiftHeld: held.shift && !shortcutHeld,
            shortcutPressed: false
        ) else { return }

        present(near: sample.point)
    }

    private func handleShortcut() {
        // While the button is down, the hardware poll owns the shortcut so a drag cannot double-toggle.
        guard !isDragging else { return }
        toggleFromShortcut(near: NSEvent.mouseLocation)
    }

    private func handleMouseUp() {
        guard isDragging else { return }
        isDragging = false
        isContentDragging = false
        keyboardPoll?.cancel()
        keyboardPoll = nil
        shakeDetector.reset()

        // onDrop sets dropEvent on this mouse-up, but that can land after the monitor.
        scheduleDropReleaseCheck()
    }

    /// The first build of this feature used Control-Shift-Space. Dropover's new-shelf
    /// shortcut is Option-Shift-Space, and a saved copy of the old default should follow it.
    private func migrateShowShelfShortcutIfNeeded() {
        let previousDefault = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .shift])
        guard KeyboardShortcuts.getShortcut(for: .showFloatingShelf) == previousDefault else { return }
        KeyboardShortcuts.setShortcut(.init(.space, modifiers: [.option, .shift]), for: .showFloatingShelf)
    }

    /// Carbon hotkeys are not delivered while another app is tracking a drag, so the
    /// configured shortcut is sampled from the hardware keyboard until the button comes up.
    private func startKeyboardPoll() {
        keyboardPoll?.cancel()
        shortcutWasHeld = shortcutIsHeld(HeldModifiers.readHardware())
        keyboardPoll = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, self.isDragging else { return }
                self.noteContentDragIfNeeded()
                self.noteShareHover()
                guard !ShelfSelectionModel.shared.isDragging else { continue }
                let held = HeldModifiers.readHardware()
                let shortcutHeld = self.shortcutIsHeld(held)
                let shortcutPressed = shortcutHeld && !self.shortcutWasHeld
                self.shortcutWasHeld = shortcutHeld
                if shortcutPressed {
                    self.toggleFromShortcut(near: NSEvent.mouseLocation)
                    continue
                }
                guard FloatingShelfTriggerPolicy.shouldPresent(
                    shelfEnabled: Defaults[.boringShelf],
                    floatingShelfEnabled: Defaults[.floatingShelf],
                    contentDragActive: self.isContentDragging,
                    shake: false,
                    shiftHeld: held.shift && !shortcutHeld,
                    shortcutPressed: false
                ) else { continue }
                self.present(near: NSEvent.mouseLocation)
            }
        }
    }

    private func toggleFromShortcut(near cursor: CGPoint) {
        guard Defaults[.boringShelf], Defaults[.floatingShelf] else { return }
        if isPresented {
            dismiss()
            return
        }
        present(near: cursor)
        scheduleNotchStyleDismiss(hasVisited: false)
    }

    private func shortcutIsHeld(_ held: HeldModifiers) -> Bool {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .showFloatingShelf) else { return false }
        let required = HeldModifiers(
            shift: shortcut.modifiers.contains(.shift),
            control: shortcut.modifiers.contains(.control),
            option: shortcut.modifiers.contains(.option),
            command: shortcut.modifiers.contains(.command)
        )
        guard held == required else { return false }
        let keyCode = CGKeyCode(shortcut.carbonKeyCode)
        return CGEventSource.keyState(.hidSystemState, key: keyCode)
    }

    private func noteContentDragIfNeeded() {
        let pasteboardChanged = dragPasteboard.changeCount != pasteboardChangeCount
        guard pasteboardChanged, !isContentDragging, DragPasteboardContent.isDroppable(dragPasteboard) else { return }
        isContentDragging = true
        shakeDetector.reset()
    }

    private func present(near cursor: CGPoint) {
        guard !isPresented else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main else { return }

        dismissTask?.cancel()
        let panel = ensurePanel()
        panel.resetAppearance()
        let frame = FloatingShelfPlacement.frame(cursor: cursor, screenFrame: screen.frame)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        isPresented = true
        Log.shelf.debug("Presented floating shelf")
    }

    private func ensurePanel() -> FloatingShelfPanel {
        if let panel {
            return panel
        }
        let panel = FloatingShelfPanel()
        self.panel = panel
        return panel
    }

    private func scheduleDropReleaseCheck() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            var shareTargeted = self.panel?.dropInteraction.dropZoneTargeting == true
            let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
            while !Task.isCancelled, ContinuousClock.now < deadline {
                if self.panel?.dropInteraction.dropZoneTargeting == true {
                    shareTargeted = true
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard !Task.isCancelled else { return }
            self.finishDragRelease(shareTargeted: shareTargeted || self.shareDropArmed)
        }
    }

    private func noteShareHover() {
        if panel?.dropInteraction.dropZoneTargeting == true {
            shareDropArmed = true
        }
    }

    private func finishDragRelease(shareTargeted: Bool) {
        guard isPresented else { return }
        let dropped = panel?.dropInteraction.dropEvent == true
        panel?.dropInteraction.dropEvent = false
        if dropped {
            if shareTargeted || SharingStateManager.shared.preventNotchClose {
                scheduleDismissAfterSharing()
            } else {
                scheduleNotchStyleDismiss()
            }
            return
        }
        if SharingStateManager.shared.preventNotchClose {
            return
        }
        dismiss()
    }

    private func scheduleDismissAfterSharing() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while !Task.isCancelled,
                  !SharingStateManager.shared.preventNotchClose,
                  ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            while !Task.isCancelled, SharingStateManager.shared.preventNotchClose {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled, self.isPresented else { return }
            self.scheduleNotchStyleDismiss()
        }
    }

    /// `hasVisited` starts false for a shortcut open. A drop already happened on the panel, so that path starts visited.
    private func scheduleNotchStyleDismiss(hasVisited: Bool = true) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            var hasVisited = hasVisited
            while !Task.isCancelled, self.isPresented {
                if self.pointerIsInsidePanel() {
                    hasVisited = true
                }
                let readyToClose = FloatingShelfDismissPolicy.shouldClose(
                    hasVisited: hasVisited,
                    pointerInside: self.pointerIsInsidePanel(),
                    sharingActive: SharingStateManager.shared.preventNotchClose
                )
                if !readyToClose {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
                try? await Task.sleep(for: .milliseconds(hoverExitDelayMilliseconds))
                guard !Task.isCancelled, self.isPresented else { return }
                if self.pointerIsInsidePanel() {
                    hasVisited = true
                }
                let stillReady = FloatingShelfDismissPolicy.shouldClose(
                    hasVisited: hasVisited,
                    pointerInside: self.pointerIsInsidePanel(),
                    sharingActive: SharingStateManager.shared.preventNotchClose
                )
                guard stillReady else { continue }
                self.dismiss()
                return
            }
        }
    }

    private func pointerIsInsidePanel() -> Bool {
        guard let panel else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    private func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard isPresented else { return }
        panel?.orderOut(nil)
        panel?.resetAppearance()
        isPresented = false
    }
}
