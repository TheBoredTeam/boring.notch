//
//  FloatingShelfPanel.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import SwiftUI

/// Drop target shown beside the pointer. It must be allowed to become key:
/// a nonactivating panel that refuses key status never receives an in-progress drag.
@MainActor
final class FloatingShelfPanel: NSPanel {
    let dropInteraction = DropInteractionState()

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: FloatingShelfPlacement.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureWindow()
        contentView = FirstMouseHostingView(rootView: FloatingShelfChrome(dropInteraction: dropInteraction))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func resetAppearance() {
        dropInteraction.dragDetectorTargeting = false
        dropInteraction.generalDropTargeting = false
        dropInteraction.dropZoneTargeting = false
        dropInteraction.dropEvent = false
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

/// Clicks on the shelf background also count, so a grab does not require a focus click first.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct FloatingShelfChrome: View {
    let dropInteraction: DropInteractionState

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
    }
}
