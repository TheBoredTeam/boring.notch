//
//  ClipboardSelectionInteraction.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import SwiftUI

struct ClipboardTileFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// SwiftUI owns selection; this small surface handles a single mouse gesture and native drag session.
struct ClipboardSelectionInteraction: NSViewRepresentable {
    let items: [ClipboardHistoryItem]
    let tileFrames: [UUID: CGRect]
    let selectedIDs: Set<UUID>
    let selectionChanged: (Set<UUID>) -> Void
    let clicked: (ClipboardHistoryItem) -> Void
    let interactionChanged: (Bool) -> Void
    let dragFailed: () -> Void

    func makeNSView(context: Context) -> ClipboardSelectionView {
        ClipboardSelectionView()
    }

    func updateNSView(_ view: ClipboardSelectionView, context: Context) {
        view.items = items
        view.tileFrames = tileFrames
        view.selectedIDs = selectedIDs
        view.selectionChanged = selectionChanged
        view.clicked = clicked
        view.interactionChanged = interactionChanged
        view.dragFailed = dragFailed
    }
}

final class ClipboardSelectionView: NSView, NSDraggingSource {
    var items: [ClipboardHistoryItem] = []
    var tileFrames: [UUID: CGRect] = [:]
    var selectedIDs: Set<UUID> = []
    var selectionChanged: (Set<UUID>) -> Void = { _ in }
    var clicked: (ClipboardHistoryItem) -> Void = { _ in }
    var interactionChanged: (Bool) -> Void = { _ in }
    var dragFailed: () -> Void = {}

    private var gesture: ClipboardSelectionGesture?
    private var mouseDownEvent: NSEvent?
    private var isInteracting = false
    private var isDragging = false
    private var dragPayload: ClipboardDragPayload?
    private var escapeMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Leave scrolling, context menus, card actions and the scrollbar to their native views.
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
              !event.modifierFlags.contains(.control) else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local), local.x < bounds.maxX - 12 else { return nil }
        if let frame = tileFrames.values.first(where: { $0.contains(local) }), local.y > frame.maxY - 34 {
            return nil
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        let point = convert(event.locationInWindow, from: nil)
        let id = items.first { tileFrames[$0.id]?.contains(point) == true }?.id
        let additive = !event.modifierFlags.isDisjoint(with: [.command, .shift])
        gesture = ClipboardSelectionGesture(start: point, itemID: id, selectedIDs: selectedIDs, additive: additive)
        setInteracting(true)
        if let gesture { selectionChanged(gesture.selectedIDs) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var gesture, !isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        let visibleFrames = tileFrames.mapValues { $0.intersection(bounds) }
            .filter { !$0.value.isNull && !$0.value.isEmpty }
        gesture.move(to: point, frames: visibleFrames)
        self.gesture = gesture
        selectionChanged(gesture.selectedIDs)
        guard gesture.hasMoved else { return }
        if gesture.startedOnSelection || !bounds.contains(point) {
            startDragging(ids: gesture.selectedIDs)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !isDragging else { return }
        if let gesture, !gesture.hasMoved, !gesture.additive,
           let item = items.first(where: { $0.id == gesture.itemID }) {
            if gesture.originalIDs.contains(item.id) {
                selectionChanged(gesture.originalIDs.subtracting([item.id]))
            } else {
                clicked(item)
            }
        }
        finishInteraction()
    }

    override func cancelOperation(_ sender: Any?) {
        if let gesture, !isDragging { selectionChanged(gesture.originalIDs) }
        if !isDragging { finishInteraction() }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, !isDragging { finishInteraction() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func startDragging(ids: Set<UUID>) {
        let selected = items.filter { ids.contains($0.id) }
        guard !selected.isEmpty, let mouseDownEvent else { return }
        let payload: ClipboardDragPayload
        do {
            payload = try ClipboardDragPayload(items: selected)
        } catch {
            finishInteraction()
            dragFailed()
            return
        }
        dragPayload = payload
        let point = convert(mouseDownEvent.locationInWindow, from: nil)
        let draggingItems = payload.writers.enumerated().map { index, writer in
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            let preview = dragImage(for: payload.previewItems[index])
            let offset = CGFloat(min(index, 3)) * 5
            draggingItem.setDraggingFrame(
                NSRect(x: point.x + offset - 40, y: point.y + offset - 30, width: 80, height: 60),
                contents: preview
            )
            return draggingItem
        }
        isDragging = true
        let session = beginDraggingSession(with: draggingItems, event: mouseDownEvent, source: self)
        session.draggingFormation = .pile
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func dragImage(for item: ClipboardHistoryItem) -> NSImage {
        let image = NSImage(size: NSSize(width: 160, height: 120))
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: 160, height: 120), xRadius: 12, yRadius: 12
        ).fill()
        switch item.content {
        case .image(_, _, let thumbnail):
            let scale = min(144 / thumbnail.size.width, 104 / thumbnail.size.height)
            let size = NSSize(width: thumbnail.size.width * scale, height: thumbnail.size.height * scale)
            thumbnail.draw(in: NSRect(
                x: (160 - size.width) / 2, y: (120 - size.height) / 2, width: size.width, height: size.height
            ))
        case .text(let text, _):
            (String(text.prefix(160)) as NSString).draw(
                in: NSRect(x: 10, y: 10, width: 140, height: 100),
                withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.white]
            )
        }
        image.unlockFocus()
        return image
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        dragPayload?.finish(completed: !operation.isEmpty)
        dragPayload = nil
        finishInteraction()
    }

    private func setInteracting(_ active: Bool) {
        guard active != isInteracting else { return }
        isInteracting = active
        if active {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window,
                      event.keyCode == 53, !self.isDragging else { return event }
                self.cancelOperation(nil)
                return nil
            }
            if let window {
                let notifications = [
                    NSWindow.willCloseNotification, NSWindow.didResignKeyNotification,
                    NSWindow.didChangeOcclusionStateNotification
                ]
                windowObservers = notifications.map { name in
                    NotificationCenter.default.addObserver(
                        forName: name, object: window, queue: .main
                    ) { [weak self] notification in
                        guard let self, !self.isDragging else { return }
                        if notification.name != NSWindow.didChangeOcclusionStateNotification
                            || self.window?.isVisible == false {
                            self.cancelOperation(nil)
                        }
                    }
                }
            }
        } else {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
            windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
            windowObservers.removeAll()
        }
        interactionChanged(active)
    }

    private func finishInteraction() {
        gesture = nil
        mouseDownEvent = nil
        setInteracting(false)
    }
}

struct ClipboardSelectionGesture {
    let start: CGPoint
    let itemID: UUID?
    let originalIDs: Set<UUID>
    let additive: Bool
    let startedOnSelection: Bool
    private var previous: CGPoint
    private(set) var hasMoved = false
    private(set) var selectedIDs: Set<UUID>

    init(start: CGPoint, itemID: UUID?, selectedIDs: Set<UUID>, additive: Bool) {
        self.start = start
        self.previous = start
        self.itemID = itemID
        self.originalIDs = selectedIDs
        self.additive = additive
        self.startedOnSelection = itemID.map { selectedIDs.contains($0) } == true && !additive
        self.selectedIDs = additive || startedOnSelection ? selectedIDs : []
        if let itemID {
            if additive, self.selectedIDs.contains(itemID) {
                self.selectedIDs.remove(itemID)
            } else {
                self.selectedIDs.insert(itemID)
            }
        }
    }

    mutating func move(to point: CGPoint, frames: [UUID: CGRect]) {
        guard hypot(point.x - start.x, point.y - start.y) > 4 || hasMoved else { return }
        hasMoved = true
        defer { previous = point }
        guard !startedOnSelection else { return }
        for (id, frame) in frames where Self.intersects(from: previous, to: point, rectangle: frame) {
            selectedIDs.insert(id)
        }
    }

    // Segment clipping also catches cards crossed between coalesced mouse events.
    static func intersects(from start: CGPoint, to end: CGPoint, rectangle: CGRect) -> Bool {
        var entry: CGFloat = 0
        var exit: CGFloat = 1
        for (origin, delta, lower, upper) in [
            (start.x, end.x - start.x, rectangle.minX, rectangle.maxX),
            (start.y, end.y - start.y, rectangle.minY, rectangle.maxY)
        ] {
            if abs(delta) < 0.0001 {
                if origin < lower || origin > upper { return false }
            } else {
                let first = (lower - origin) / delta
                let second = (upper - origin) / delta
                entry = max(entry, min(first, second))
                exit = min(exit, max(first, second))
                if entry > exit { return false }
            }
        }
        return true
    }
}
