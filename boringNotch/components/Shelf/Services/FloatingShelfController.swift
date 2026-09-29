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
    private var isMouseDown = false
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
    private var menuObservers: [NSObjectProtocol] = []
    /// A context menu opened over the panel. The pointer leaves the panel to pick an item,
    /// so the close timer must wait for the menu rather than read the pointer.
    private var panelMenu: NSMenu?
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var isNotchOpen: () -> Bool = { false }

    private init() {}

    func start(isNotchOpen: @escaping () -> Bool) {
        guard mouseDownMonitor == nil else { return }
        self.isNotchOpen = isNotchOpen
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

    /// Hiding the panel mid-share would drop the picker's anchor, and hiding it while an item
    /// is being dragged out would end that drag, so those cases keep the panel.
    func notchDidOpen() {
        guard !SharingStateManager.shared.preventNotchClose,
              !ShelfSelectionModel.shared.isDragging else { return }
        // Called from the notch's SwiftUI update. Starting the close animation there lets it
        // land in the same frame as that update, so the panel vanishes instead of animating.
        Task { @MainActor [weak self] in
            self?.dismiss()
        }
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

        // Delivered synchronously: a queued block would not run until the menu's tracking loop ends.
        menuObservers = [
            NotificationCenter.default.addObserver(
                forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil
            ) { [weak self] notification in
                let menu = notification.object as? NSMenu
                MainActor.assumeIsolated {
                    self?.menuDidBeginTracking(menu)
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil
            ) { [weak self] notification in
                let menu = notification.object as? NSMenu
                MainActor.assumeIsolated {
                    self?.menuDidEndTracking(menu)
                }
            },
        ]
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
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers = []
    }

    private func menuDidBeginTracking(_ menu: NSMenu?) {
        guard isPresented, panelMenu == nil,
              panel?.frame.contains(NSEvent.mouseLocation) == true else { return }
        panelMenu = menu
    }

    private func menuDidEndTracking(_ menu: NSMenu?) {
        if menu === panelMenu { panelMenu = nil }
    }

    private func handleMouseDown() {
        pasteboardChangeCount = dragPasteboard.changeCount
        isMouseDown = true
        isContentDragging = false
        shareDropArmed = false
        shakeDetector = PointerShakeDetector(sensitivity: Defaults[.floatingShelfShakeSensitivity])
        startKeyboardPoll()
    }

    private func handleMouseDragged(sample: PointerSample) {
        guard isMouseDown else { return }
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
        guard !isMouseDown else { return }
        toggleFromShortcut(near: NSEvent.mouseLocation)
    }

    private func handleMouseUp() {
        guard isMouseDown else { return }
        isMouseDown = false
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
                guard !Task.isCancelled, self.isMouseDown else { return }
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
            notchOpen: isNotchOpen(),
            contentDragActive: isContentDragging,
            shake: shake,
            shakeTriggerEnabled: Defaults[.floatingShelfShakeTrigger],
            shiftHeld: held.contains(.shift) && !shortcutHeld,
            shiftTriggerEnabled: Defaults[.floatingShelfShiftTrigger],
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
            notchOpen: isNotchOpen(),
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
        let frame = FloatingShelfPlacement.frame(cursor: cursor, screenFrame: screen.frame)
        panel.setFrame(frame, display: true)
        panel.show(growingFrom: FloatingShelfPlacement.growthAnchor(cursor: cursor, frame: frame))
        isPresented = true
        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        Log.shelf.debug("Presented floating shelf")
    }

    private func ensurePanel() -> FloatingShelfPanel {
        if let panel {
            return panel
        }
        let panel = FloatingShelfPanel()
        panel.onEscape = { [weak self] in self?.dismiss() }
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
        if SharingStateManager.shared.preventNotchClose || (dropped && shareDropArmed) {
            scheduleDismissAfterSharing()
        } else if dropped {
            scheduleNotchStyleDismiss()
        } else {
            dismiss()
        }
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
            grabbingItem: ShelfSelectionModel.shared.isDragging,
            menuOpen: panelMenu != nil
        )
    }

    private func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard isPresented else { return }
        isPresented = false
        panel?.hide { [weak panel] in panel?.resetAppearance() }
    }
}
