//
//  ShelfItemInteractionView.swift
//  boringNotch
//

import AppKit
import Defaults
import SwiftUI

protocol ShelfItemInteractionSurface: AnyObject {}

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
        view.viewModel = viewModel
        view.dragPreviewProvider = renderDragPreview
        view.onPrimaryClick = onPrimaryClick
        view.onContextClick = onContextClick
    }

    private func renderDragPreview() -> NSImage {
        let renderer = ImageRenderer(content: dragPreview())
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage ?? viewModel.presentationIcon
    }

    final class InteractionView: NSView, NSDraggingSource, ShelfItemInteractionSurface {
        var item: ShelfItem?
        weak var viewModel: ShelfItemViewModel?
        var dragPreviewProvider: (() -> NSImage)?
        var onPrimaryClick: ((NSEvent, NSView) -> Void)?
        var onContextClick: ((NSEvent, NSView) -> Void)?

        private let dragThreshold: CGFloat = 3
        private var mouseDownEvent: NSEvent?
        var shelfState: ShelfStateViewModel = .shared
        var beginPreparedDrag: (([NSDraggingItem], NSEvent) -> Void)?
        private var preparationTask: Task<Void, Never>?
        private var draggedURLs: [URL] = []
        private var draggedItems: [ShelfItem] = []

        override func rightMouseDown(with event: NSEvent) {
            onContextClick?(event, self)
        }

        override func mouseDown(with event: NSEvent) {
            cancelDragPreparation()
            mouseDownEvent = event
            onPrimaryClick?(event, self)
        }

        override func mouseDragged(with event: NSEvent) {
            guard preparationTask == nil else { return }
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
        }

        override func mouseUp(with event: NSEvent) {
            cancelDragPreparation()
            super.mouseUp(with: event)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { cancelDragPreparation() }
            super.viewWillMove(toWindow: newWindow)
        }

        func cancelDragPreparation() {
            mouseDownEvent = nil
            preparationTask?.cancel()
            preparationTask = nil
        }

        private func startDragSession(with event: NSEvent) {
            guard let item else { return }
            let selectedItems = ShelfSelectionModel.shared.selectedItems(in: shelfState.items)
            let itemsToDrag = selectedItems.count > 1
                && selectedItems.contains(where: { $0.id == item.id })
                ? selectedItems
                : [item]

            preparationTask = Task { [weak self, shelfState] in
                let exports = await Self.prepareDragExports(for: itemsToDrag, shelfState: shelfState)
                guard !Task.isCancelled, let self, self.mouseDownEvent != nil,
                      self.shelfState.items.contains(where: { $0.id == item.id }) else { return }
                self.preparationTask = nil
                self.mouseDownEvent = nil
                guard !exports.isEmpty else { return }
                self.draggedItems = exports.map(\.item)
                self.draggedURLs = exports.compactMap { $0.payload as? NSURL }
                    .map { $0 as URL }.filter { $0.startAccessingSecurityScopedResource() }
                let image = self.dragPreviewProvider?() ?? self.viewModel?.presentationIcon ?? NSImage()
                let draggingItems = exports.map { export in
                    let draggingItem = NSDraggingItem(pasteboardWriter: export.payload)
                    draggingItem.setDraggingFrame(NSRect(origin: .zero, size: image.size), contents: image)
                    return draggingItem
                }
                if let beginPreparedDrag = self.beginPreparedDrag {
                    beginPreparedDrag(draggingItems, event)
                } else {
                    self.beginDraggingSession(with: draggingItems, event: event, source: self)
                }
            }
        }

        /// Resolve at the native export boundary, using the same request owner as
        /// presentation and actions. Prepared payloads live only for this gesture.
        static func prepareDragExports(
            for items: [ShelfItem], shelfState: ShelfStateViewModel
        ) async -> [(item: ShelfItem, payload: any NSPasteboardWriting)] {
            var exports: [(item: ShelfItem, payload: any NSPasteboardWriting)] = []
            for item in items {
                guard !Task.isCancelled else { return [] }
                let writer: any NSPasteboardWriting
                switch item.kind {
                case .file:
                    guard let file = await shelfState.resolveFile(
                        for: item, intent: .userInitiated, refresh: true
                    ) else { continue }
                    writer = file.url as NSURL
                case .text(let string):
                    let pasteboardItem = NSPasteboardItem()
                    pasteboardItem.setString(string, forType: .string)
                    writer = pasteboardItem
                case .link(let url):
                    let pasteboardItem = NSPasteboardItem()
                    pasteboardItem.setString(url.absoluteString, forType: .URL)
                    pasteboardItem.setString(url.absoluteString, forType: .string)
                    writer = pasteboardItem
                }
                exports.append((item, writer))
            }
            guard !Task.isCancelled else { return [] }
            return exports.filter { export in shelfState.items.contains { $0.id == export.item.id } }
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
