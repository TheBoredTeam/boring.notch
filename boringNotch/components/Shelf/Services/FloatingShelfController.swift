//
//  FloatingShelfController.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Defaults
import KeyboardShortcuts

/// Presents a drop shelf beside the pointer while a file drag is in progress.
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
        shakeDetector.reset()
        startKeyboardPoll()
    }

    private func handleMouseDragged(sample: PointerSample) {
        guard isDragging else { return }
        noteContentDragIfNeeded()
        guard isContentDragging, !ShelfSelectionModel.shared.isDragging else { return }

        let shaken = shakeDetector.add(sample)
        let held = HeldModifiers.readHardware()
        guard FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: Defaults[.boringShelf],
            floatingShelfEnabled: Defaults[.floatingShelf],
            contentDragActive: true,
            shake: shaken,
            shiftHeld: held.shift,
            shortcutPressed: shortcutIsHeld(held)
        ) else { return }

        present(near: sample.point)
    }

    private func handleShortcut() {
        guard FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: Defaults[.boringShelf],
            floatingShelfEnabled: Defaults[.floatingShelf],
            contentDragActive: isContentDragging,
            shake: false,
            shiftHeld: false,
            shortcutPressed: true
        ) else { return }

        present(near: NSEvent.mouseLocation)
    }

    private func handleMouseUp() {
        guard isDragging else { return }
        isDragging = false
        isContentDragging = false
        keyboardPoll?.cancel()
        keyboardPoll = nil
        shakeDetector.reset()

        // onDrop sets dropEvent on this mouse-up, but that can land after the monitor.
        // The notch waits the same 500ms, then stays open when the drop actually landed.
        scheduleDropReleaseCheck()
    }

    /// Carbon hotkeys are not delivered while another app is tracking a drag, so the
    /// configured shortcut is sampled from the hardware keyboard until the button comes up.
    private func startKeyboardPoll() {
        keyboardPoll?.cancel()
        keyboardPoll = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, self.isDragging else { return }
                self.noteContentDragIfNeeded()
                guard self.isContentDragging, !ShelfSelectionModel.shared.isDragging else { continue }
                let held = HeldModifiers.readHardware()
                guard FloatingShelfTriggerPolicy.shouldPresent(
                    shelfEnabled: Defaults[.boringShelf],
                    floatingShelfEnabled: Defaults[.floatingShelf],
                    contentDragActive: true,
                    shake: false,
                    shiftHeld: held.shift,
                    shortcutPressed: self.shortcutIsHeld(held)
                ) else { continue }
                self.present(near: NSEvent.mouseLocation)
            }
        }
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
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.finishDragRelease()
        }
    }

    /// A drop into ShelfView or FileShareView sets dropEvent and must leave this panel up.
    /// The share picker is anchored to it, and BoringViewModel.close() likewise stays open
    /// while SharingStateManager.preventNotchClose is set.
    private func finishDragRelease() {
        guard isPresented else { return }
        if panel?.dropInteraction.dropEvent == true {
            panel?.dropInteraction.dropEvent = false
            Log.shelf.debug("Floating shelf kept open after drop")
            return
        }
        if SharingStateManager.shared.preventNotchClose {
            return
        }
        dismiss()
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
