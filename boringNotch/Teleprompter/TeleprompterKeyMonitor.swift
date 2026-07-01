//
//  TeleprompterKeyMonitor.swift
//  boringNotch
//
//  Arrow-key / space control for the teleprompter.
//
//  The notch window is a non-activating panel that can never become key, so a
//  normal key handler in the view would never fire. Instead we install a
//  *global* event monitor, which observes keystrokes while another app (or
//  nothing) is focused — exactly the situation when you're reading aloud. This
//  requires the app to be trusted for Accessibility (the same permission the
//  HUD feature uses); if it isn't, the monitor simply never fires and the
//  on-screen buttons and trackpad scrolling still work.
//

import AppKit

@MainActor
final class TeleprompterKeyMonitor {
    enum Key { case up, down, left, right, space }

    private var monitor: Any?
    private let onKey: (Key) -> Void

    init(onKey: @escaping (Key) -> Void) {
        self.onKey = onKey
    }

    func start() {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let key = Self.map(event) else { return }
            Task { @MainActor in self?.onKey(key) }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private static func map(_ event: NSEvent) -> Key? {
        switch Int(event.keyCode) {
        case 126: return .up
        case 125: return .down
        case 123: return .left
        case 124: return .right
        case 49:  return .space
        default:  return nil
        }
    }
}
