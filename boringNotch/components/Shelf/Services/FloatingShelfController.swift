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
    private var acceptedDrop = false
    private var pasteboardChangeCount = -1
    private var dismissTask: Task<Void, Never>?

    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?
    private let dragPasteboard = NSPasteboard(name: .drag)

    private init() {}

    func start() {
        guard mouseDownMonitor == nil else { return }
        installMonitors()
        KeyboardShortcuts.onKeyDown(for: .showFloatingShelf) { [weak self] in
            Task { @MainActor in
                self?.handleShortcut()
            }
        }
    }

    func stop() {
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
            let shiftHeld = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
            Task { @MainActor in
                self?.handleMouseDragged(sample: sample, shiftHeld: shiftHeld)
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
        acceptedDrop = false
        shakeDetector.reset()
    }

    private func handleMouseDragged(sample: PointerSample, shiftHeld: Bool) {
        guard isDragging else { return }
        noteContentDragIfNeeded()
        guard isContentDragging, !ShelfSelectionModel.shared.isDragging else { return }

        let shaken = shakeDetector.add(sample)
        guard FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: Defaults[.boringShelf],
            floatingShelfEnabled: Defaults[.floatingShelf],
            contentDragActive: true,
            shake: shaken,
            shiftHeld: shiftHeld,
            shortcutPressed: false
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
        shakeDetector.reset()

        // The drop lands in this same mouse-up turn. Decide after it has been delivered.
        Task { @MainActor in
            if self.acceptedDrop {
                self.scheduleDismiss()
            } else {
                self.dismiss()
            }
            self.acceptedDrop = false
        }
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
        panel.onPerformDrop = { [weak self] pasteboard in
            self?.performDrop(from: pasteboard) ?? false
        }
        self.panel = panel
        return panel
    }

    private func performDrop(from pasteboard: NSPasteboard) -> Bool {
        let providers = DragPasteboardContent.itemProviders(from: pasteboard)
        guard !providers.isEmpty else { return false }
        ShelfStateViewModel.shared.load(providers)
        acceptedDrop = true
        panel?.dropModel.isTargeted = false
        panel?.dropModel.acceptedCount = providers.count
        Log.shelf.notice("Floating shelf accepted \(providers.count, privacy: .public) item(s)")
        return true
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self.dismiss()
        }
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
