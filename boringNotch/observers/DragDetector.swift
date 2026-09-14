// SPDX-License-Identifier: GPL-3.0-only

import Cocoa

/// Observes drags outside our native destination. Native destination callbacks
/// take over once the pointer reaches the panel; this detector never receives data.
final class DragDetector: NSObject {
    var onDragEntersNotchRegion: (() -> Void)?
    var onDragExitsNotchRegion: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var region: (() -> CGRect)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var endTimer: Timer?
    private var pasteboardChangeCount = -1
    private var isDragging = false
    private var isContentDragging = false
    private var hasEnteredNotchRegion = false
    private let dragPasteboard = NSPasteboard(name: .drag)

    func startMonitoring() {
        stopMonitoring()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] in self?.handle($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask.union(.keyDown)) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            finish()
            pasteboardChangeCount = dragPasteboard.changeCount
            isDragging = true
        case .leftMouseDragged:
            guard isDragging else { return }
            if !isContentDragging, dragPasteboard.changeCount != pasteboardChangeCount {
                isContentDragging = dragPasteboard.pasteboardItems?.contains {
                    ShelfTransferTypes.supports(typeIdentifiers: $0.types.map(\.rawValue))
                } ?? false
                if isContentDragging {
                    // A source can consume the terminating mouse-up. This check
                    // only runs during a content drag and never requests key access.
                    endTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self,
                                                   selector: #selector(checkForDragEnd), userInfo: nil, repeats: true)
                }
            }
            guard isContentDragging else { return }
            let contains = region?().contains(NSEvent.mouseLocation) ?? false
            if contains != hasEnteredNotchRegion {
                hasEnteredNotchRegion = contains
                if contains { onDragEntersNotchRegion?() }
                else { onDragExitsNotchRegion?() }
            }
        case .leftMouseUp:
            finish()
        case .keyDown where event.keyCode == 53:
            finish()
        default:
            break
        }
    }

    @objc private func checkForDragEnd() {
        if NSEvent.pressedMouseButtons & 1 == 0 { finish() }
    }

    private func finish() {
        let wasContentDragging = isContentDragging
        endTimer?.invalidate()
        endTimer = nil
        isDragging = false
        isContentDragging = false
        hasEnteredNotchRegion = false
        pasteboardChangeCount = -1
        if wasContentDragging { onDragEnded?() }
    }

    func stopMonitoring() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
        finish()
    }

    deinit { stopMonitoring() }
}
