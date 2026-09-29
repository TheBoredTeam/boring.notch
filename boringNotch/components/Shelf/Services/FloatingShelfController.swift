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

    private static let chordModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    private var shakeDetector = PointerShakeDetector()
    private var panel: FloatingShelfPanel?
    private var isPresented = false
    private var isDragging = false
    private var isContentDragging = false
    private var pasteboardChangeCount = -1
    private var dismissTask: Task<Void, Never>?
    private var keyboardPoll: Task<Void, Never>?
    /// `dropZoneTargeting` clears before the mouse-up handler runs, so a share hover is latched here.
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
        let held = Self.hardwareModifiers()
        if dragTriggerFires(shake: shaken, held: held, shortcutHeld: shortcutIsHeld(held)) {
            present(near: sample.point)
        }
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
        noteShareHover()
        scheduleDropReleaseCheck()
    }

    /// Carbon hotkeys are not delivered while another app is tracking a drag, so the
    /// configured shortcut is sampled from the hardware keyboard until the button comes up.
    private func startKeyboardPoll() {
        keyboardPoll?.cancel()
        shortcutWasHeld = shortcutIsHeld(Self.hardwareModifiers())
        keyboardPoll = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, self.isDragging else { return }
                self.noteContentDragIfNeeded()
                self.noteShareHover()
                guard !ShelfSelectionModel.shared.isDragging else { continue }
                let held = Self.hardwareModifiers()
                let shortcutHeld = self.shortcutIsHeld(held)
                let shortcutPressed = shortcutHeld && !self.shortcutWasHeld
                self.shortcutWasHeld = shortcutHeld
                if shortcutPressed {
                    self.toggleFromShortcut(near: NSEvent.mouseLocation)
                } else if self.dragTriggerFires(shake: false, held: held, shortcutHeld: shortcutHeld) {
                    self.present(near: NSEvent.mouseLocation)
                }
            }
        }
    }

    /// Option-Shift-Space includes Shift. While that chord is down, Shift must not reopen the shelf.
    private func dragTriggerFires(shake: Bool, held: NSEvent.ModifierFlags, shortcutHeld: Bool) -> Bool {
        FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: Defaults[.boringShelf],
            floatingShelfEnabled: Defaults[.floatingShelf],
            contentDragActive: isContentDragging,
            shake: shake,
            shiftHeld: held.contains(.shift) && !shortcutHeld,
            shortcutPressed: false
        )
    }

    private func toggleFromShortcut(near cursor: CGPoint) {
        if isPresented {
            dismiss()
            return
        }
        guard FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: Defaults[.boringShelf],
            floatingShelfEnabled: Defaults[.floatingShelf],
            contentDragActive: isContentDragging,
            shake: false,
            shiftHeld: false,
            shortcutPressed: true
        ) else { return }
        present(near: cursor)
        // A background app's cursor changes only apply over its key window. During a file
        // drag this must not run, since moving key status would cancel the drag.
        if !isContentDragging {
            panel?.makeKey()
        }
        scheduleNotchStyleDismiss(hasVisited: false)
    }

    /// A drag owned by another app does not update `NSEvent.modifierFlags`.
    /// `CGEventFlags` uses the same bits for these four keys.
    private static func hardwareModifiers() -> NSEvent.ModifierFlags {
        let flags = CGEventSource.flagsState(.hidSystemState)
        return NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)).intersection(chordModifiers)
    }

    private func shortcutIsHeld(_ held: NSEvent.ModifierFlags) -> Bool {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .showFloatingShelf),
              held == shortcut.modifiers.intersection(Self.chordModifiers) else { return false }
        return CGEventSource.keyState(.hidSystemState, key: CGKeyCode(shortcut.carbonKeyCode))
    }

    private func noteContentDragIfNeeded() {
        let pasteboardChanged = dragPasteboard.changeCount != pasteboardChangeCount
        guard pasteboardChanged, !isContentDragging, DragPasteboardContent.isDroppable(dragPasteboard) else { return }
        isContentDragging = true
        shakeDetector.reset()
    }

    private func noteShareHover() {
        if panel?.dropInteraction.dropZoneTargeting == true {
            shareDropArmed = true
        }
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

    /// onDrop sets `dropEvent` on this mouse-up, but that can land after the global monitor.
    /// The notch waits the same 500ms before reading it.
    private func scheduleDropReleaseCheck() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.finishDragRelease()
        }
    }

    private func finishDragRelease() {
        guard isPresented else { return }
        let dropped = panel?.dropInteraction.dropEvent == true
        panel?.dropInteraction.dropEvent = false
        if dropped {
            if shareDropArmed || SharingStateManager.shared.preventNotchClose {
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

    /// Loading the dropped files and presenting the picker is asynchronous, so allow a few
    /// seconds for the share session to begin before falling back to the hover rule.
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
                guard self.readyToClose(hasVisited: &hasVisited) else {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
                try? await Task.sleep(for: .milliseconds(hoverExitDelayMilliseconds))
                guard !Task.isCancelled, self.isPresented else { return }
                if self.readyToClose(hasVisited: &hasVisited) {
                    self.dismiss()
                    return
                }
            }
        }
    }

    private func readyToClose(hasVisited: inout Bool) -> Bool {
        let pointerInside = panel?.frame.contains(NSEvent.mouseLocation) == true
        if pointerInside {
            hasVisited = true
        }
        return FloatingShelfDismissPolicy.shouldClose(
            hasVisited: hasVisited,
            pointerInside: pointerInside,
            sharingActive: SharingStateManager.shared.preventNotchClose,
            grabbingItem: ShelfSelectionModel.shared.isDragging
        )
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
