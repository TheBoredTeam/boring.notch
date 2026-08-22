//
//  ShelfItemInteractionView.swift
//  boringNotch
//

import AppKit
import Defaults
import SwiftUI

/// A narrow AppKit bridge for Shelf pointer and native drag interactions.
struct ShelfItemInteractionView<DragPreview: View>: NSViewRepresentable {
    let item: ShelfItem
    let viewModel: ShelfItemViewModel
    @ViewBuilder let dragPreview: () -> DragPreview
    let onPrimaryClick: (NSEvent, NSView) -> Void
    let onContextClick: (NSEvent, NSView) -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        update(nsView)
    }

    private func update(_ view: InteractionView) {
        view.item = item
        view.dragPreviewProvider = renderDragPreview
        view.onPrimaryClick = onPrimaryClick
        view.onContextClick = onContextClick
    }

    private func renderDragPreview() -> NSImage {
        let renderer = ImageRenderer(content: dragPreview())
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage ?? viewModel.thumbnail ?? item.icon
    }

    final class InteractionView: NSView, NSDraggingSource {
        var item: ShelfItem!
        var dragPreviewProvider: (() -> NSImage)?
        var onPrimaryClick: ((NSEvent, NSView) -> Void)?
        var onContextClick: ((NSEvent, NSView) -> Void)?

        private let dragThreshold: CGFloat = 3
        private var mouseDownEvent: NSEvent?
        private var draggedURLs: [URL] = []
        private var draggedItems: [ShelfItem] = []

        override func rightMouseDown(with event: NSEvent) {
            onContextClick?(event, self)
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            onPrimaryClick?(event, self)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let mouseDownEvent else {
                super.mouseDragged(with: event)
                return
            }

            let dragDistance = hypot(
                event.locationInWindow.x - mouseDownEvent.locationInWindow.x,
                event.locationInWindow.y - mouseDownEvent.locationInWindow.y
            )

            guard dragDistance > dragThreshold else {
                super.mouseDragged(with: event)
                return
            }

            startDragSession(with: event)
            self.mouseDownEvent = nil
        }

        private func startDragSession(with event: NSEvent) {
            let selectedItems = ShelfSelectionModel.shared.selectedItems(
                in: ShelfStateViewModel.shared.items
            )
            let itemsToDrag = selectedItems.count > 1
                && selectedItems.contains(where: { $0.id == item.id })
                ? selectedItems
                : [item]

            draggedItems = itemsToDrag
            let draggingItems = itemsToDrag.compactMap(makeDraggingItem)

            guard !draggingItems.isEmpty else { return }
            beginDraggingSession(with: draggingItems, event: event, source: self)
        }

        private func makeDraggingItem(for item: ShelfItem) -> NSDraggingItem? {
            guard let writer = pasteboardWriter(for: item) else { return nil }

            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            let image = dragPreviewProvider?() ?? item.icon
            draggingItem.setDraggingFrame(
                NSRect(origin: .zero, size: image.size),
                contents: image
            )
            return draggingItem
        }

        private func pasteboardWriter(for item: ShelfItem) -> (any NSPasteboardWriting)? {
            switch item.kind {
            case .file:
                guard let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) else {
                    let fallback = NSPasteboardItem()
                    fallback.setString(item.displayName, forType: .string)
                    return fallback
                }

                if url.startAccessingSecurityScopedResource() {
                    draggedURLs.append(url)
                    NSLog("🔐 Started security-scoped access for drag: \(url.path)")
                }
                return url as NSURL

            case .text(let string):
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(string, forType: .string)
                return pasteboardItem

            case .link(let url):
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(url.absoluteString, forType: .URL)
                pasteboardItem.setString(url.absoluteString, forType: .string)
                return pasteboardItem
            }
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            if Defaults[.copyOnDrag] {
                return .copy
            }

            switch context {
            case .outsideApplication:
                return [.copy, .move]
            case .withinApplication:
                return [.copy, .move, .generic]
            @unknown default:
                return .copy
            }
        }

        func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
            ShelfSelectionModel.shared.beginDrag()
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            ShelfSelectionModel.shared.endDrag()

            for url in draggedURLs {
                url.stopAccessingSecurityScopedResource()
                NSLog("🔐 Stopped security-scoped access after drag: \(url.path)")
            }
            draggedURLs.removeAll()

            if Defaults[.autoRemoveShelfItems] && !operation.isEmpty {
                for item in draggedItems {
                    ShelfStateViewModel.shared.remove(item)
                }
            }
            draggedItems.removeAll()
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
            false
        }
    }
}
