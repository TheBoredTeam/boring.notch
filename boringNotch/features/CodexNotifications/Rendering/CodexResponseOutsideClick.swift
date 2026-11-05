import AppKit
import SwiftUI

/// Observe clicks without consuming them or changing pointer-exit timing.
struct CodexResponseOutsideClick: NSViewRepresentable {
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.onOutsideClick = onOutsideClick
        return view
    }

    func updateNSView(_ nsView: Anchor, context: Context) {
        nsView.onOutsideClick = onOutsideClick
    }

    static func dismantleNSView(_ nsView: Anchor, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class Anchor: NSView {
        var onOutsideClick: () -> Void = {}
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private static let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        // This background tracks bounds; it must never take a click from content.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.clicks) { [weak self] event in
                self?.handle(event)
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.clicks) { [weak self] event in
                self?.handle(event)
            }
        }

        func handle(_ event: NSEvent) {
            guard Self.clicks.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue)),
                  let window, window.isVisible else { return }
            let sourceWindow = event.windowNumber == window.windowNumber ? window : event.window
            let point = sourceWindow.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
            let rect = window.convertToScreen(convert(bounds, to: nil))
            if !rect.contains(point) { onOutsideClick() }
        }

        func stopMonitoring() {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            localMonitor = nil
            globalMonitor = nil
        }
    }
}
