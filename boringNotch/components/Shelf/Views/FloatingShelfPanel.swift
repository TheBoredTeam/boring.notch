//
//  FloatingShelfPanel.swift
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
final class FloatingShelfPanel: NSPanel {
    let dropInteraction = DropInteractionState()
    private let presentation = FloatingShelfPresentation()

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: FloatingShelfPlacement.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureWindow()
        contentView = FirstMouseHostingView(
            rootView: FloatingShelfChrome(dropInteraction: dropInteraction, presentation: presentation)
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func resetAppearance() {
        dropInteraction.dragDetectorTargeting = false
        dropInteraction.generalDropTargeting = false
        dropInteraction.dropZoneTargeting = false
        dropInteraction.dropEvent = false
    }

    /// The content scales in SwiftUI; the window alpha fades separately because the
    /// window shadow does not follow SwiftUI content as it scales.
    func show(growingFrom anchor: CGPoint) {
        presentation.anchor = UnitPoint(x: anchor.x, y: anchor.y)
        ignoresMouseEvents = false
        if !isVisible {
            alphaValue = 0
        }
        orderFrontRegardless()
        withAnimation(StandardAnimations.open) {
            presentation.isShown = true
        }
        fade(to: 1, completion: nil)
    }

    func hide(completion: @escaping () -> Void) {
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
    }
}

@Observable
private final class FloatingShelfPresentation {
    var isShown = false
    var anchor: UnitPoint = .top
}

/// Clicks on the shelf background also count, so a grab does not require a focus click first.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct FloatingShelfChrome: View {
    let dropInteraction: DropInteractionState
    let presentation: FloatingShelfPresentation

    var body: some View {
        ShelfView(dropInteraction: dropInteraction, animation: nil)
            // Inside the notch this 12pt inset is the gap around the shelf row.
            // The extra top-corner inset only exists to clear NotchShape's ears.
            .padding(12)
            .frame(
                width: FloatingShelfPlacement.panelSize.width,
                height: FloatingShelfPlacement.panelSize.height
            )
            .background(.black)
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadiusInsets.opened.bottom, style: .continuous)
            )
            .scaleEffect(presentation.isShown ? 1 : 0.9, anchor: presentation.anchor)
    }
}
