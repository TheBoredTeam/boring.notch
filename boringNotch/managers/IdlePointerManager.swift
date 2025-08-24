//
//  IdlePointerManager.swift
//  boring.notch
//
//  Created for auto-shrink functionality
//

import Cocoa

extension Notification.Name {
    static let bnPointerDidGoIdle = Notification.Name("bnPointerDidGoIdle")
}

final class IdlePointerManager {
    private var idleTimer: Timer?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var lastPoint: NSPoint = NSEvent.mouseLocation

    /// Seconds of stillness before considered idle
    var idleInterval: TimeInterval = 5.0

    /// Pixels of allowable jitter before we consider it movement
    var movementTolerance: CGFloat = 2.0

    /// If true, detector is active
    var isEnabled: Bool = true {
        didSet { isEnabled ? start() : stop() }
    }

    /// Install monitors (once) and arm the timer
    func start() {
        // Always re-arm timer so callers can reset the idle window via start()
        lastPoint = NSEvent.mouseLocation
        resetIdleTimer()

        // Install monitors only once
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            ) { [weak self] _ in
                self?.handleMouseMoved()
            }
        }
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            ) { [weak self] e in
                self?.handleMouseMoved()
                return e
            }
        }
    }

    /// Re-arm the timer without touching monitors
    func arm() {
        lastPoint = NSEvent.mouseLocation
        resetIdleTimer()
    }

    func stop() {
        idleTimer?.invalidate(); idleTimer = nil
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
                #if DEBUG
                print("[IdlePointer] idle fired → posting bnPointerDidGoIdle")
                #endif
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
