//
//  FloatingShelfController.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Defaults

/// The notch drag detector stays responsible for opening the notch itself.
/// This controller only decides when a content drag should also show the shelf beside the pointer.
@MainActor
final class FloatingShelfController {
    static let shared = FloatingShelfController()

    private var shakeDetector = PointerShakeDetector()
    private var panel: FloatingShelfPanel?
    private var isPresented = false
    private var trackingContentDrag = false
    private var dismissTask: Task<Void, Never>?
    /// `dropZoneTargeting` clears before the mouse-up handler runs, so a share hover is latched here.
    private var shareDropArmed = false

    private var dragSubscription: UUID?
    private var menuObservers: [NSObjectProtocol] = []
    /// A context menu opened over the panel. The pointer leaves the panel to pick an item,
    /// so the close timer must wait for the menu rather than read the pointer.
    private var panelMenu: NSMenu?
    private var isNotchOpen: () -> Bool = { false }

    private init() {}

    func start(isNotchOpen: @escaping () -> Bool) {
        guard dragSubscription == nil else { return }
        self.isNotchOpen = isNotchOpen
        dragSubscription = DragSession.shared.subscribe(
            onMove: { [weak self] point in
                let sample = PointerSample(point: point, time: ProcessInfo.processInfo.systemUptime)
                Task { @MainActor in
                    self?.handleContentDragMoved(sample)
                }
            },
            onEnd: { [weak self] in
                Task { @MainActor in
                    self?.handleDragEnded()
                }
            }
        )
        installMenuObservers()
        // Create the panel before any drag so its drop registration already exists.
        _ = ensurePanel()
    }

    func stop() {
        if let dragSubscription {
            DragSession.shared.unsubscribe(dragSubscription)
            self.dragSubscription = nil
        }
        removeMenuObservers()
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

    private func installMenuObservers() {
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

    private func removeMenuObservers() {
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers = []
        panelMenu = nil
    }

    private func menuDidBeginTracking(_ menu: NSMenu?) {
        guard isPresented, panelMenu == nil,
              panel?.frame.contains(NSEvent.mouseLocation) == true else { return }
        panelMenu = menu
    }

    private func menuDidEndTracking(_ menu: NSMenu?) {
        if menu === panelMenu { panelMenu = nil }
    }

    private func handleContentDragMoved(_ sample: PointerSample) {
        if !trackingContentDrag {
            trackingContentDrag = true
            shareDropArmed = false
            shakeDetector = PointerShakeDetector(sensitivity: Defaults[.floatingShelfShakeSensitivity])
        }
        noteShareHover()
        guard !ShelfSelectionModel.shared.isDragging else { return }

        let shaken = shakeDetector.add(sample)
        if dragTriggerFires(shake: shaken, shiftHeld: Self.shiftIsHeld()) {
            present(near: sample.point)
        }
    }

    private func handleDragEnded() {
        let wasContentDrag = trackingContentDrag
        trackingContentDrag = false
        shakeDetector.reset()
        noteShareHover()
        guard wasContentDrag || isPresented else { return }
        scheduleDropReleaseCheck()
    }

    private func dragTriggerFires(shake: Bool, shiftHeld: Bool) -> Bool {
        FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: Defaults[.boringShelf],
            floatingShelfEnabled: Defaults[.floatingShelf],
            notchOpen: isNotchOpen(),
            contentDragActive: true,
            shake: shake,
            shakeTriggerEnabled: Defaults[.floatingShelfShakeTrigger],
            shiftHeld: shiftHeld,
            shiftTriggerEnabled: Defaults[.floatingShelfShiftTrigger]
        )
    }

    /// A drag owned by another app does not update `NSEvent.modifierFlags`.
    private static func shiftIsHeld() -> Bool {
        let flags = CGEventSource.flagsState(.hidSystemState)
        return NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)).contains(.shift)
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

    /// A drop already happened on the panel, so the pointer counts as having visited.
    private func scheduleNotchStyleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            var hasVisited = true
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
