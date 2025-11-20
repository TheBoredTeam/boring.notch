//
//  DragDetector.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-20.
//

import Cocoa
import Foundation

final class DragDetector {

    // MARK: - Public types / callbacks

    typealias VoidCallback = () -> Void
    typealias PositionCallback = (_ globalPoint: CGPoint) -> Void
    typealias ConcludeCallback = (_ files: [URL], _ urls: [URL], _ strings: [String]) -> Void

    // Callbacks
    var onDragStart: VoidCallback?
    var onDragMove: PositionCallback?
    var onDragEnd: ConcludeCallback?
    var onDragEntersNotchRegion: VoidCallback?
    var onDragExitsNotchRegion: VoidCallback?

    // MARK: - Internal state

    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?

    private var initialChangeCount: Int = -1
    private var isDragging: Bool = false
    private var isContentDragging: Bool = false
    private var hasEnteredNotchRegion: Bool = false

    // Region where open notch would occupy
    private let notchRegion: CGRect

    // MARK: - Initialization

    init(notchRegion: CGRect) {
        self.notchRegion = notchRegion
    }

    // MARK: - Start / Stop monitoring

    func startMonitoring() {
        stopMonitoring() // be idempotent

        // Mouse down: record pasteboard changeCount and start a fresh tracking session
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            let pb = NSPasteboard(name: .drag)
            self.initialChangeCount = pb.changeCount
            self.isDragging = true
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
        }

        // Mouse dragged: periodically check pasteboard changeCount to know whether
        // the user is dragging actual content. Track position against notch region.
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            guard let self = self else { return }
            guard self.isDragging else { return }

            let pb = NSPasteboard(name: .drag)
            let currentChangeCount = pb.changeCount

            // If change count differs from initial, the system has placed drag data onto the pasteboard,
            // meaning this is a content drag (file/URL) instead of, e.g., moving a window.
            if currentChangeCount != self.initialChangeCount {
                if !self.isContentDragging {
                    self.isContentDragging = true
                    self.onDragStart?()
                }
            }

            // Only process location detection if it's a content drag
            if self.isContentDragging {
                let loc = NSEvent.mouseLocation
                self.onDragMove?(loc)

                // Check if drag entered the notch region
                if self.notchRegion.contains(loc) {
                    if !self.hasEnteredNotchRegion {
                        self.hasEnteredNotchRegion = true
                        self.onDragEntersNotchRegion?()
                    }
                } else {
                    if self.hasEnteredNotchRegion {
                        self.hasEnteredNotchRegion = false
                        self.onDragExitsNotchRegion?()
                    }
                }
            }
        }

        // Mouse up: conclude drag session and parse pasteboard for content if there was content
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self = self else { return }
            guard self.isDragging else { return }

            let pb = NSPasteboard(name: .drag)
            let currentChangeCount = pb.changeCount
            let hadContent = (currentChangeCount != self.initialChangeCount)

            self.isDragging = false
            self.initialChangeCount = -1
            self.hasEnteredNotchRegion = false

            // Always call onDragEnd if we were content dragging, to clean up UI
            if self.isContentDragging {
                if hadContent {
                    // Parse the pasteboard for files/URLs/strings
                    let (files, urls, strings) = self.parseDragPasteboard(pasteboard: pb)
                    self.onDragEnd?(files, urls, strings)
                } else {
                    // Should not happen if isContentDragging was true, but safe fallback
                    self.onDragEnd?([], [], [])
                }
            }

            self.isContentDragging = false
        }
    }

    func stopMonitoring() {
        if let m = mouseDownMonitor {
            NSEvent.removeMonitor(m)
            mouseDownMonitor = nil
        }
        if let m = mouseDraggedMonitor {
            NSEvent.removeMonitor(m)
            mouseDraggedMonitor = nil
        }
        if let m = mouseUpMonitor {
            NSEvent.removeMonitor(m)
            mouseUpMonitor = nil
        }
        isDragging = false
        isContentDragging = false
        hasEnteredNotchRegion = false
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Pasteboard parsing

    /// Attempt to extract file URLs, generic URLs, and plain strings from the drag pasteboard.
    private func parseDragPasteboard(pasteboard pb: NSPasteboard) -> (files: [URL], urls: [URL], strings: [String]) {
        var files: [URL] = []
        var urls: [URL] = []
        var strings: [String] = []

        guard let items = pb.pasteboardItems else {
            return (files, urls, strings)
        }

        for item in items {
            // File URLs (type: fileURL)
            if let fileString = item.string(forType: .fileURL), let fileURL = URL(string: fileString) {
                // fileURL strings from pasteboard are typically proper file:// URLs
                if fileURL.isFileURL {
                    files.append(fileURL)
                    continue
                }
            }

            // Regular URL type (could be http(s) or other schemes)
            if let urlString = item.string(forType: .URL), let url = URL(string: urlString) {
                urls.append(url)
                continue
            }

            // Some drag sources only put a plain string; try to interpret it as a URL
            if let plain = item.string(forType: .string) {
                strings.append(plain)
                if let maybeURL = URL(string: plain), maybeURL.scheme != nil {
                    urls.append(maybeURL)
                }
            }
        }

        // Deduplicate
        files = Array(Set(files))
        urls = Array(Set(urls))
        strings = Array(Set(strings))

        return (files, urls, strings)
    }
}
