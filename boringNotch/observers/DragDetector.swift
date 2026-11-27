//
//  DragDetector.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-20.
//

import Cocoa

/// One global watch for a file, link, or text drag. Notch detectors and the floating drop target
/// subscribe instead of each installing their own mouse monitors.
final class DragSession {
    static let shared = DragSession()

    private struct Subscriber {
        var onMove: (CGPoint) -> Void
        var onEnd: () -> Void
    }

    private var subscribers: [UUID: Subscriber] = [:]
    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?

    private var pasteboardChangeCount = -1
    private var isDragging = false
    private var isContentDragging = false
    private let dragPasteboard = NSPasteboard(name: .drag)

    private init() {}

    /// Moves arrive only after the drag pasteboard holds droppable content. `onEnd` arrives
    /// on mouse-up for that content drag, not for a click that never picked anything up.
    @discardableResult
    func subscribe(onMove: @escaping (CGPoint) -> Void, onEnd: @escaping () -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = Subscriber(onMove: onMove, onEnd: onEnd)
        if subscribers.count == 1 {
            installMonitors()
        }
        return id
    }

    func unsubscribe(_ id: UUID) {
        guard subscribers.removeValue(forKey: id) != nil else { return }
        if subscribers.isEmpty {
            removeMonitors()
        }
    }

    private func installMonitors() {
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self else { return }
            self.pasteboardChangeCount = self.dragPasteboard.changeCount
            self.isDragging = true
            self.isContentDragging = false
        }

        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            guard let self, self.isDragging else { return }
            self.noteContentDragIfNeeded()
            guard self.isContentDragging else { return }
            let point = NSEvent.mouseLocation
            let subscribers = Array(self.subscribers.values)
            for subscriber in subscribers {
                subscriber.onMove(point)
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self, self.isDragging else { return }
            let endedContentDrag = self.isContentDragging
            self.isDragging = false
            self.isContentDragging = false
            self.pasteboardChangeCount = -1
            // A plain click never became a content drag. Notifying subscribers would
            // look like the drag that opened the floating target had ended.
            guard endedContentDrag else { return }
            let subscribers = Array(self.subscribers.values)
            for subscriber in subscribers {
                subscriber.onEnd()
            }
        }
    }

    private func noteContentDragIfNeeded() {
        let pasteboardChanged = dragPasteboard.changeCount != pasteboardChangeCount
        guard pasteboardChanged, !isContentDragging, ShelfDropService.canAccept(dragPasteboard) else { return }
        isContentDragging = true
    }

    private func removeMonitors() {
        for monitor in [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor] {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
        isDragging = false
        isContentDragging = false
        pasteboardChangeCount = -1
    }
}

final class DragDetector {
    typealias VoidCallback = () -> Void
    typealias PositionCallback = (_ globalPoint: CGPoint) -> Void

    var onDragEntersNotchRegion: VoidCallback?
    var onDragExitsNotchRegion: VoidCallback?
    var onDragMove: PositionCallback?

    private var subscription: UUID?
    private var hasEnteredNotchRegion = false
    private let notchRegion: CGRect

    init(notchRegion: CGRect) {
        self.notchRegion = notchRegion
    }

    func startMonitoring() {
        stopMonitoring()
        subscription = DragSession.shared.subscribe(
            onMove: { [weak self] point in
                self?.handleMove(point)
            },
            onEnd: { [weak self] in
                self?.handleEnd()
            }
        )
    }

    func stopMonitoring() {
        if let subscription {
            DragSession.shared.unsubscribe(subscription)
            self.subscription = nil
        }
        hasEnteredNotchRegion = false
    }

    private func handleMove(_ point: CGPoint) {
        onDragMove?(point)

        let containsMouse = notchRegion.contains(point)
        if containsMouse && !hasEnteredNotchRegion {
            hasEnteredNotchRegion = true
            onDragEntersNotchRegion?()
        } else if !containsMouse && hasEnteredNotchRegion {
            hasEnteredNotchRegion = false
            onDragExitsNotchRegion?()
        }
    }

    private func handleEnd() {
        hasEnteredNotchRegion = false
    }

    deinit {
        stopMonitoring()
    }
}
