//
//  FloatingShelfPanel.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import SwiftUI

@MainActor
final class FloatingShelfDropModel: ObservableObject {
    @Published var acceptedCount: Int?
}

/// Drop target shown beside the pointer. It must be allowed to become key:
/// a nonactivating panel that refuses key status never receives an in-progress drag.
@MainActor
final class FloatingShelfPanel: NSPanel {
    let dropModel = FloatingShelfDropModel()
    let dropInteraction = DropInteractionState()

    var onShelfDrop: (([NSItemProvider]) -> Bool)?

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: FloatingShelfPlacement.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureWindow()
        contentView = NSHostingView(rootView: FloatingShelfChrome(
            model: dropModel,
            dropInteraction: dropInteraction,
            onShelfDrop: { [weak self] providers in
                self?.onShelfDrop?(providers) ?? false
            }
        ))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func resetAppearance() {
        dropModel.acceptedCount = nil
        dropInteraction.dragDetectorTargeting = false
        dropInteraction.generalDropTargeting = false
        dropInteraction.dropZoneTargeting = false
        dropInteraction.dropEvent = false
    }

    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        hasShadow = true
        backgroundColor = .clear
        isMovable = false
        hidesOnDeactivate = false
        // Above normal windows, still inside the level range a drag session will hit-test.
        // screenSaver level draws the panel but the drag passes through it.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }
}

private struct FloatingShelfChrome: View {
    @ObservedObject var model: FloatingShelfDropModel
    let dropInteraction: DropInteractionState
    var onShelfDrop: ([NSItemProvider]) -> Bool

    var body: some View {
        @Bindable var interaction = dropInteraction

        HStack(alignment: .center, spacing: Self.spacing) {
            FileShareView(dropInteraction: dropInteraction)
                .frame(width: Self.tileLength, height: Self.tileLength)
            dropWell
                .frame(maxWidth: .infinity)
                .frame(height: Self.tileLength)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $interaction.dragDetectorTargeting) { providers in
                    onShelfDrop(providers)
                }
        }
        .padding(Self.outerPadding)
        .frame(
            width: FloatingShelfPlacement.panelSize.width,
            height: FloatingShelfPlacement.panelSize.height,
            alignment: .center
        )
    }

    private static let outerPadding: CGFloat = 12
    private static let spacing: CGFloat = 12
    private static var tileLength: CGFloat {
        FloatingShelfPlacement.panelSize.height - (outerPadding * 2)
    }

    private var dropWell: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black.opacity(0.78))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        dropInteraction.dragDetectorTargeting ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.28),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8])
                    )
            )
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: model.acceptedCount == nil ? "tray.and.arrow.down" : "checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2)
                    Text(model.acceptedCount == nil ? "Drop files here" : "Added to shelf")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
    }
}
