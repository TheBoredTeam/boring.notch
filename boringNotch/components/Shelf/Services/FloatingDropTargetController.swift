//
//  FloatingDropTargetController.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Defaults

/// The notch drag detector stays responsible for opening the notch itself.
/// This controller only decides when a content drag should also show a drop target beside the pointer.
@MainActor
final class FloatingDropTargetController {
    static let shared = FloatingDropTargetController()

    private var shakeDetector = PointerShakeDetector()
    private var panel: FloatingDropTargetPanel?
    private var isPresented = false
    private var trackingContentDrag = false
    private var dismissTask: Task<Void, Never>?
    private var previewReady = false
    private var awaitingPreview = false

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
            shakeDetector = PointerShakeDetector(sensitivity: Defaults[.floatingDropTargetShakeSensitivity])
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
        FloatingDropTargetTriggerPolicy.shouldPresent(
            shelfEnabled: Defaults[.boringShelf],
            floatingDropTargetEnabled: Defaults[.floatingDropTarget],
            notchOpen: isNotchOpen(),
            contentDragActive: true,
            shake: shake,
            shakeTriggerEnabled: Defaults[.floatingDropTargetShakeTrigger],
            shiftHeld: shiftHeld,
            shiftTriggerEnabled: Defaults[.floatingDropTargetShiftTrigger]
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
        previewReady = false
        awaitingPreview = false
        let panel = ensurePanel()
        let frame = FloatingDropTargetPlacement.frame(cursor: cursor, screenFrame: screen.frame)
        panel.setFrame(frame, display: true)
        panel.show(growingFrom: FloatingDropTargetPlacement.growthAnchor(cursor: cursor, frame: frame))
        isPresented = true
        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        Log.shelf.debug("Presented floating drop target")
    }

    private func ensurePanel() -> FloatingDropTargetPanel {
        if let panel {
            return panel
        }
        let panel = FloatingDropTargetPanel()
        panel.onPreviewEvent = { [weak self] event in
            self?.handlePreview(event)
        }
        self.panel = panel
        return panel
    }

    /// onDrop sets `dropEvent` on this mouse-up, but that can land after the global monitor.
    /// The notch waits the same 500ms before reading it.
    private func scheduleDropReleaseCheck() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(dropEventAcknowledgementDelayMilliseconds))
            guard !Task.isCancelled else { return }
            self.finishDragRelease()
        }
    }

    private func finishDragRelease() {
        guard isPresented else { return }
        let dropped = panel?.dropInteraction.dropEvent == true
        panel?.dropInteraction.dropEvent = false
        if dropped {
            if previewReady {
                armPointerLeave()
            } else {
                awaitingPreview = true
            }
            return
        }
        // A drop already committed this panel to staying up. A later drag that misses
        // the square does not close it while that preview is unresolved or the pointer is still inside.
        if awaitingPreview || panel?.isWaitingForPointerExit == true {
            return
        }
        dismiss()
    }

    /// `load` can finish before or after the mouse-up acknowledgement. Pointer-leave starts
    /// only once this drop's items are in the well, so a slow file stays on screen.
    private func handlePreview(_ event: FloatingDropTargetPreviewEvent) {
        guard isPresented else { return }
        switch event {
        case .started:
            previewReady = false
            panel?.suspendPointerExit()
        case .resolved(let itemCount):
            previewReady = true
            panel?.showPreview(itemCount: itemCount)
            guard awaitingPreview else { return }
            awaitingPreview = false
            armPointerLeave()
        case .changed(let itemCount):
            guard previewReady else { return }
            if itemCount == 0 {
                dismiss()
            } else {
                panel?.showPreview(itemCount: itemCount)
            }
        }
    }

    private func armPointerLeave() {
        panel?.dismissWhenPointerLeaves { [weak self] in
            self?.dismiss()
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        previewReady = false
        awaitingPreview = false
        guard isPresented else { return }
        isPresented = false
        panel?.hide { [weak panel] in panel?.resetAppearance() }
    }
}

enum FloatingDropTargetTriggerPolicy {
    static func shouldPresent(
        shelfEnabled: Bool,
        floatingDropTargetEnabled: Bool,
        notchOpen: Bool,
        contentDragActive: Bool,
        shake: Bool,
        shakeTriggerEnabled: Bool = true,
        shiftHeld: Bool,
        shiftTriggerEnabled: Bool = true
    ) -> Bool {
        // The open notch already shows the shelf, so a drop target is never stacked beside it.
        guard shelfEnabled, floatingDropTargetEnabled, !notchOpen, contentDragActive else { return false }
        return (shake && shakeTriggerEnabled) || (shiftHeld && shiftTriggerEnabled)
    }
}
