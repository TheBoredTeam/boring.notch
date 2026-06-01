//
//  TrashBucketView.swift
//  boringNotch
//
//  A conflict-free way to delete shelf items: drag an item onto this red bucket and
//  it's removed. Unlike the hover ✕ (which fights the drag NSView for the same click),
//  dropping is unambiguous. The drop is handled by an AppKit drop target because the
//  within-app `NSDraggingSession` doesn't reliably fire SwiftUI's `.onDrop`.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TrashBucketView: View {
    @StateObject private var selection = ShelfSelectionModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHot = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isHot ? Color.red.opacity(0.22) : Color.red.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isHot ? Color.red.opacity(0.9) : Color.red.opacity(0.35),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6])
                        )
                )

            Image(systemName: "trash")
                .font(.system(size: 22, weight: .medium))
                .symbolVariant(isHot ? .fill : .none)
                .foregroundStyle(isHot ? Color.red : Color.red.opacity(0.7))
                .scaleEffect((isHot && !reduceMotion) ? 1.12 : 1)

            // AppKit drop target sits on top to reliably catch the within-app drag.
            TrashDropTarget(isHot: $isHot) {
                let items = selection.activeDragItems
                guard !items.isEmpty else { return }
                for item in items { ShelfActionService.remove(item) }
            }
        }
        .frame(width: 56)
        .aspectRatio(1, contentMode: .fit)
        .animation(Motion.resolved(Motion.hover, reduceMotion: reduceMotion), value: isHot)
        .help("Drag here to delete")
        .accessibilityLabel("Trash")
        .accessibilityHint("Drop shelf items here to remove them")
    }
}

// MARK: - AppKit drop target

private struct TrashDropTarget: NSViewRepresentable {
    @Binding var isHot: Bool
    let onDrop: () -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.onHotChange = { hot in
            DispatchQueue.main.async { isHot = hot }
        }
        view.onPerform = onDrop
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        nsView.onHotChange = { hot in
            DispatchQueue.main.async { isHot = hot }
        }
        nsView.onPerform = onDrop
    }

    final class DropView: NSView {
        var onHotChange: ((Bool) -> Void)?
        var onPerform: (() -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.fileURL, .string, .URL, .png, .tiff])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            onHotChange?(true)
            // `.copy` is always in the drag source's accepted mask (even with
            // copyOnDrag on). No file promise is written, so this implies no on-disk
            // copy — the bucket just removes the items from the shelf model.
            return .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            onHotChange?(false)
        }

        override func draggingEnded(_ sender: NSDraggingInfo) {
            onHotChange?(false)
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            onHotChange?(false)
            onPerform?()
            return true
        }
    }
}
