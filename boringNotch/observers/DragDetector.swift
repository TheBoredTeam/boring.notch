//
//  DragDetector.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-20.
//

import AppKit

final class DragDetector {

    typealias VoidCallback = () -> Void

    var onDragEntersNotchRegion: VoidCallback?
    var onDragExitsNotchRegion: VoidCallback?

    private let panel: HitPanel
    private let hitView: HitView

    init(screen: NSScreen) {
        let view = HitView()
        hitView = view

        panel = HitPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .mainMenu + 4
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        panel.contentView = view

        view.onDragEntered = { [weak self] in self?.onDragEntersNotchRegion?() }
        view.onDragExited = { [weak self] in self?.onDragExitsNotchRegion?() }

        updateFrame(for: screen)
    }

    func startMonitoring() {
        // Join the notch CGSSpace so the dragging session enumerates this panel
        // alongside BoringNotchSkyLightWindow rather than below it. Without this
        // the notch panel (which sits in the max-level space but has no
        // registered drag types) shadows the hit panel, so draggingEntered: is
        // never delivered.
        NotchSpaceManager.shared.notchSpace.windows.insert(panel)
        panel.orderFrontRegardless()
    }

    func stopMonitoring() {
        NotchSpaceManager.shared.notchSpace.windows.remove(panel)
        panel.orderOut(nil)
        panel.close()
    }

    deinit {
        stopMonitoring()
    }

    private func updateFrame(for screen: NSScreen) {
        let frame = screen.frame
        let rect = NSRect(
            x: frame.midX - openNotchSize.width / 2,
            y: frame.maxY - openNotchSize.height,
            width: openNotchSize.width,
            height: openNotchSize.height
        )
        panel.setFrame(rect, display: false)
        hitView.frame = NSRect(origin: .zero, size: rect.size)
    }
}

private final class HitPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HitView: NSView {

    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([
            .fileURL,
            .URL,
            .string,
            .tiff,
            .png,
            .pdf,
            .rtf,
            .html,
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("public.url"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Pass clicks through when no drag is in progress so the menu bar / windows
    // beneath this transparent overlay stay clickable. The dragging session
    // populates the .drag pasteboard before evaluating destinations, so a
    // non-empty type list is a reliable signal that a drag is active.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard NSPasteboard(name: .drag).types?.isEmpty == false else { return nil }
        return super.hitTest(point)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        false
    }
}
