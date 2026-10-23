//
//  FloatingDropTargetPanel.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Defaults
import Observation
import SwiftUI

/// Drop target shown beside the pointer. It must be allowed to become key:
/// a nonactivating panel that refuses key status never receives an in-progress drag.
@MainActor
final class FloatingDropTargetPanel: NSPanel {
    let dropInteraction = DropInteractionState()
    private let presentation = FloatingDropTargetPresentation()
    private var pointerExitTask: Task<Void, Never>?
    private var onPointerExit: (@MainActor () -> Void)?

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: FloatingDropTargetPlacement.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureWindow()
        contentView = FirstMouseHostingView(
            rootView: FloatingDropTargetChrome(
                dropInteraction: dropInteraction,
                presentation: presentation,
                onHoverChanged: { [weak self] in self?.handlePointerHover($0) }
            )
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func resetAppearance() {
        cancelPointerExitDismissal()
        dropInteraction.reset()
    }

    /// The content scales in SwiftUI; the window alpha fades separately because the
    /// window shadow does not follow SwiftUI content as it scales.
    func show(growingFrom anchor: CGPoint) {
        cancelPointerExitDismissal()
        presentation.anchor = UnitPoint(x: anchor.x, y: anchor.y)
        ignoresMouseEvents = false
        if !isVisible {
            alphaValue = 0
        }
        presentation.generation += 1
        orderFrontRegardless()
        withAnimation(StandardAnimations.open) {
            presentation.isShown = true
        }
        fade(to: 1, completion: nil)
    }

    func hide(completion: @escaping () -> Void) {
        cancelPointerExitDismissal()
        ignoresMouseEvents = true
        withAnimation(StandardAnimations.close) {
            presentation.isShown = false
        }
        fade(to: 0) { [weak self] in
            // A show() during the fade takes the panel back, so it must stay on screen.
            guard let self, !self.presentation.isShown else { return }
            self.orderOut(nil)
            completion()
        }
    }

    func dismissWhenPointerLeaves(_ action: @escaping @MainActor () -> Void) {
        onPointerExit = action
        handlePointerHover(frame.contains(NSEvent.mouseLocation))
    }

    private func handlePointerHover(_ inside: Bool) {
        pointerExitTask?.cancel()
        pointerExitTask = nil
        guard !inside, onPointerExit != nil else { return }
        pointerExitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(hoverExitDelayMilliseconds))
            guard !Task.isCancelled,
                  let self,
                  !self.frame.contains(NSEvent.mouseLocation),
                  let onPointerExit = self.onPointerExit else {
                return
            }
            self.onPointerExit = nil
            self.pointerExitTask = nil
            onPointerExit()
        }
    }

    private func cancelPointerExitDismissal() {
        pointerExitTask?.cancel()
        pointerExitTask = nil
        onPointerExit = nil
    }

    private func fade(to alpha: CGFloat, completion: (@MainActor () -> Void)?) {
        let duration = Defaults[.enableOpeningAnimation] ? 0.2 / Defaults[.animationSpeedMultiplier] : 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated {
                completion?()
            }
        }
    }

    private func configureWindow() {
        isOpaque = false
        hasShadow = true
        backgroundColor = .clear
        isMovable = false
        hidesOnDeactivate = false
        // Above normal windows, still inside the level range a drag session will hit-test.
        // screenSaver level draws the panel but the drag passes through it.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Borderless windows have no visible title, so VoiceOver would otherwise announce an unnamed window.
        setAccessibilityTitle(String(localized: "Drop target"))
    }
}

@Observable
private final class FloatingDropTargetPresentation {
    var isShown = false
    var anchor: UnitPoint = .top
    var generation = 0
}

/// Clicks on the shelf background also count, so a grab does not require a focus click first.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct FloatingDropTargetChrome: View {
    let dropInteraction: DropInteractionState
    let presentation: FloatingDropTargetPresentation
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        ShelfDropWell(
            dropInteraction: dropInteraction,
            animation: nil,
            showsShelvedItems: false,
            appearanceSession: presentation.generation
        )
            // Same inset the notch uses around the shelf row.
            .padding(12)
            .frame(
                width: FloatingDropTargetPlacement.panelSize.width,
                height: FloatingDropTargetPlacement.panelSize.height
            )
            .background(.black)
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadiusInsets.opened.bottom, style: .continuous)
            )
            .scaleEffect(presentation.isShown ? 1 : 0.9, anchor: presentation.anchor)
            .onHover(perform: onHoverChanged)
    }
}
