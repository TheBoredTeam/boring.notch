//  DropCatcher.swift
//  IslandNotch
//
//  Purpose: A passive, AppKit-level drop target parked over the notch.
//           SwiftUI `.onDrop` on the DynamicNotch panel proved unreliable for
//           Finder file drags (the shelf target materialises mid-drag and never
//           registers as a destination). AppKit `NSDraggingDestination` handles a
//           real drag session deterministically.
//
//           Modelled on Lakr233/NotchDrop: there is NO global mouse monitor and
//           NO always-on-top "armed" window (that approach turned the whole
//           top-center of the screen into a dead zone you couldn't drag windows
//           through). Instead `hitTest` only claims the cursor while a *file* drag
//           is genuinely in flight — detected via the live drag pasteboard — so
//           hovers, clicks, and window-title drags all pass straight through and
//           the notch's own hover-to-expand keeps working.
//  Layer: Window

import AppKit
import UniformTypeIdentifiers

/// The view that actually accepts the drag. Reports dropped file URLs / images.
final class DropCatcherView: NSView {
    var onDropURLs: (([URL]) -> Void)?
    var onDropImage: ((NSImage) -> Void)?
    var onDragChange: ((Bool) -> Void)?

    private static let legacyFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .fileURL,
            .png,
            .tiff,
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
            Self.legacyFilenames,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// True only while an actual drag session carrying files/images is active.
    /// A plain click (no drag pasteboard content) or a window-title drag (no file
    /// URLs on the drag pasteboard) both fail this check, so the catcher stays
    /// transparent and the event falls through to whatever is underneath.
    private var fileDragInFlight: Bool {
        guard NSEvent.pressedMouseButtons != 0 else { return false }
        let dragPasteboard = NSPasteboard(name: .drag)
        let classes: [AnyClass] = [NSURL.self, NSImage.self]
        return dragPasteboard.canReadObject(forClasses: classes, options: nil)
    }

    // Claim the cursor only during a live file drag; pass everything else through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        fileDragInFlight ? super.hitTest(point) : nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragChange?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragChange?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let urlOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: urlOptions) as? [URL], !urls.isEmpty {
            Log.store.debug("DropCatcher got \(urls.count) URL(s)")
            onDropURLs?(urls)
            onDragChange?(false)
            return true
        }
        if let legacyPaths = pb.propertyList(forType: Self.legacyFilenames) as? [String] {
            let urls = legacyPaths.map { URL(fileURLWithPath: $0) }
            if !urls.isEmpty {
                Log.store.debug("DropCatcher got \(urls.count) legacy path(s)")
                onDropURLs?(urls)
                onDragChange?(false)
                return true
            }
        }
        if let images = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage], let image = images.first {
            Log.store.debug("DropCatcher got image")
            onDropImage?(image)
            onDragChange?(false)
            return true
        }
        Log.store.debug("DropCatcher: no usable items on pasteboard")
        onDragChange?(false)
        return false
    }
}

/// Borderless, non-activating, transparent panel that hosts the catcher over the
/// notch region. Never becomes key, so it doesn't steal focus mid-drag. Sits just
/// above the menu bar so it can receive a file drag dropped onto the notch, but
/// `DropCatcherView.hitTest` keeps it transparent except during a live file drag.
final class DropCatcherWindow: NSPanel {
    let catcher: DropCatcherView

    /// Just above the menu bar — high enough to catch a file drag over the notch,
    /// low enough that it never behaves like a screensaver-level overlay.
    private static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)

    init() {
        catcher = DropCatcherView(frame: .zero)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.level
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = catcher
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
