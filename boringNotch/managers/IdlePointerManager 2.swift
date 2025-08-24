//
//  IdlePointerManager.swift
//  boring.notch
//
//  Created for auto-shrink functionality
//

import Cocoa

// Notification name fired when pointer is still for N seconds
extension Notification.Name {
    static let bnPointerDidGoIdle = Notification.Name("bnPointerDidGoIdle")
}

/// Watches global mouse movement and posts a notification
/// after `idleInterval` seconds of stillness.
final class IdlePointerManager {
    private var idleTimer: Timer?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var lastPoint: NSPoint = NSEvent.mouseLocation

    /// Seconds of stillness before idle is triggered
    var idleInterval: TimeInterval = 5.0

    /// Pixels of allowable jitter (to ignore trackpad noise)
    var movementTolerance: CGFloat = 2.0

    /// Enable/disable the detector
    var isEnabled: Bool = true {
        didSet { isEnabled ? start() : stop() }
    }

    // MARK: - Lifecycle
    func start() {
        guard globalMouseMonitor == nil else { return }

        lastPoint = NSEvent.mouseLocation
        resetIdleTimer()

        // Global monitor (when app is not key)
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            self?.handleMouseMoved()
        }

        // Local monitor (when app is key)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] e in
            self?.handleMouseMoved()
            return e
        }
    }

    func stop() {
        idleTimer?.invalidate()
        idleTimer = nil
        if let gm = globalMouseMonitor { NSEvent.removeMonitor(gm) }
        if let lm = localMouseMonitor { NSEvent.removeMonitor(lm) }
        globalMouseMonitor = nil
        localMouseMonitor   = nil
    }

    deinit { stop() }

    // MARK: - Private
    private func handleMouseMoved() {
        guard isEnabled else { return }
        let p = NSEvent.mouseLocation
        if distance(p, lastPoint) > movementTolerance {
            lastPoint = p
            resetIdleTimer()
        }
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleInterval, repeats: false) { [weak self] _ in
            guard let self = self, self.isEnabled else { return }
            let cur = NSEvent.mouseLocation
            if self.distance(cur, self.lastPoint) <= self.movementTolerance {
                NotificationCenter.default.post(name: .bnPointerDidGoIdle, object: nil)
            } else {
                self.lastPoint = cur
                self.resetIdleTimer()
            }
        }
        RunLoop.main.add(idleTimer!, forMode: .common)
    }

    private func distance(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return CGFloat(hypot(dx, dy))
    }
}