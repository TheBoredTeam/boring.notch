//
//  NotchSpaceManager.swift
//  boringNotch
//
//  Created by Alexander Greco on 2024-10-27.
//


class NotchSpaceManager {
    static let shared = NotchSpaceManager()
    let notchSpace: CGSSpace
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {
        notchSpace = CGSSpace(level: 2147483647) // Max level
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenLockStateChanged), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenLockStateChanged), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)


        // Set up the event tap to detect a lack of events (indicative of lock, but not definitive)
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.mouseMoved.rawValue)
        guard let eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: CGEventMask(eventMask), callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in

            return Unmanaged.passRetained(event)
        }, userInfo: nil) else {
            print("Failed to create event tap")
            return
        }

        self.eventTap = eventTap

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.commonModes)
    }

    private func stopMonitoring() {
        DistributedNotificationCenter.default().removeObserver(self)

        if let eventTap = eventTap {
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.commonModes)
        }

        eventTap = nil
        runLoopSource = nil
    }

    @objc private func screenLockStateChanged(_ notification: Notification) {
        let isLocked = notification.name == NSNotification.Name("com.apple.screenIsLocked")
        print("Screen is \(isLocked ? "locked" : "unlocked")")
    }
}
