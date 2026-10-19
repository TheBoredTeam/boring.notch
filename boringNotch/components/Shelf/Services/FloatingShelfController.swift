//
//  FloatingShelfController.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Defaults

/// The notch drag detector stays responsible for opening the notch itself.
/// This controller only decides when a content drag should also show a drop target beside the pointer.
@MainActor
final class FloatingShelfController {
    static let shared = FloatingShelfController()

    private var shakeDetector = PointerShakeDetector()
    private var panel: FloatingShelfPanel?
    private var isPresented = false
    private var trackingContentDrag = false
    private var dismissTask: Task<Void, Never>?

    private var dragSubscription: UUID?
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
        // Create the panel before any drag so its drop registration already exists.
        _ = ensurePanel()
    }

    func stop() {
        if let dragSubscription {
            DragSession.shared.unsubscribe(dragSubscription)
            self.dragSubscription = nil
        }
        dismiss()
    }

    /// Called from the notch's SwiftUI update. Starting the close animation there lets it
    /// land in the same frame as that update, so the panel vanishes instead of animating.
    func notchDidOpen() {
        Task { @MainActor [weak self] in
            self?.dismiss()
        }
    }

    private func handleContentDragMoved(_ sample: PointerSample) {
        if !trackingContentDrag {
            trackingContentDrag = true
            shakeDetector = PointerShakeDetector(sensitivity: Defaults[.floatingShelfShakeSensitivity])
        }

        let shaken = shakeDetector.add(sample)
        if dragTriggerFires(shake: shaken, shiftHeld: Self.shiftIsHeld()) {
            present(near: sample.point)
        }
    }

    private func handleDragEnded() {
        let wasContentDrag = trackingContentDrag
        trackingContentDrag = false
        shakeDetector.reset()
        guard wasContentDrag else { return }
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
        if dropped {
            showDroppedItemThenDismiss()
        } else {
            dismiss()
        }
    }

    /// The file is shelved asynchronously. Wait until it is in the shelf, leave it on screen
    /// long enough to see, then use the same pointer-leave close as the notch.
    private func showDroppedItemThenDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while !Task.isCancelled,
                  ShelfStateViewModel.shared.isLoading,
                  ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled, self.isPresented else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, self.isPresented else { return }
            self.scheduleNotchStyleDismiss()
        }
    }

    private func scheduleNotchStyleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            while !Task.isCancelled, self.isPresented {
                let pointerInside = self.panel?.frame.contains(NSEvent.mouseLocation) == true
                guard FloatingShelfDismissPolicy.shouldClose(pointerInside: pointerInside) else {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
                try? await Task.sleep(for: .milliseconds(hoverExitDelayMilliseconds))
                guard !Task.isCancelled, self.isPresented else { return }
                let stillInside = self.panel?.frame.contains(NSEvent.mouseLocation) == true
                if FloatingShelfDismissPolicy.shouldClose(pointerInside: stillInside) {
                    self.dismiss()
                    return
                }
            }
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard isPresented else { return }
        isPresented = false
        panel?.hide { [weak panel] in panel?.resetAppearance() }
    }
}
