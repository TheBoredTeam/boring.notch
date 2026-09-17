//
//  CaptureOverlay.swift
//  boringNotch
//
//  The full-screen overlay used to pick what to capture: a rubber-band drag
//  for an area, or a hover-highlight for a window.
//
//  One borderless window per display, above everything, swallowing mouse and
//  keyboard while it is up. Deliberately AppKit rather than SwiftUI: this has
//  to sit above the menu bar on every screen, take key focus from whatever was
//  in front, and track raw mouse drags — all of which are window-level
//  behaviours SwiftUI has no vocabulary for.
//

import AppKit
import Foundation

/// What the overlay is being used to pick.
enum CaptureOverlayMode {
    case area
    /// Hover-highlight over the supplied window frames (global AppKit coords).
    case window([CapturableWindow])
    /// Same drag as `.area`, but reports the rectangle instead of capturing —
    /// an on-screen ruler.
    case measure
}

enum CaptureOverlayResult {
    case area(rect: CGRect, screen: NSScreen)
    case window(CapturableWindow)
    case measured(CGRect)
    case cancelled
}

@MainActor
final class CaptureOverlayController {
    static let shared = CaptureOverlayController()

    private var windows: [CaptureOverlayWindow] = []
    private var completion: ((CaptureOverlayResult) -> Void)?
    private var escapeMonitor: Any?

    private init() {}

    var isPresenting: Bool { !windows.isEmpty }

    func present(mode: CaptureOverlayMode, completion: @escaping (CaptureOverlayResult) -> Void) {
        // Re-entrancy guard: a second Escape-less overlay stacked on the first
        // would leave the screen covered with no way back.
        guard !isPresenting else { return }
        self.completion = completion

        // One window per screen. A single window spanning the union of all
        // displays works until someone has a vertically offset monitor, where
        // the union contains dead space the overlay would still cover.
        windows = NSScreen.screens.map { screen in
            let window = CaptureOverlayWindow(screen: screen, mode: mode)
            window.onFinish = { [weak self] result in
                self?.finish(result)
            }
            window.orderFrontRegardless()
            return window
        }

        NSApp.activate(ignoringOtherApps: true)

        // Escape must work regardless of which screen's overlay has key
        // focus, so it is watched globally rather than per window.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Escape
            self?.finish(.cancelled)
            return nil
        }
    }

    private func finish(_ result: CaptureOverlayResult) {
        // The overlay is torn down *before* the completion runs: the capture
        // that follows would otherwise photograph the overlay itself.
        let completion = self.completion
        self.completion = nil

        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()

        // One runloop turn so the windows are really off screen before the
        // capture reads the framebuffer.
        DispatchQueue.main.async {
            completion?(result)
        }
    }
}

/// One screen's worth of overlay.
final class CaptureOverlayWindow: NSWindow {
    var onFinish: ((CaptureOverlayResult) -> Void)?

    private let overlayScreen: NSScreen
    private let overlayView: CaptureOverlayView

    init(screen: NSScreen, mode: CaptureOverlayMode) {
        overlayScreen = screen
        overlayView = CaptureOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size), mode: mode, screen: screen)

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the menu bar and full-screen apps, but below the system's own
        // alerts. `.screenSaver` is the conventional level for this.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        // Never let the overlay end up in a screen recording of itself, or in
        // Mission Control.
        sharingType = .none

        contentView = overlayView
        overlayView.onFinish = { [weak self] result in
            self?.onFinish?(result)
        }
    }

    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var screenForOverlay: NSScreen { overlayScreen }
}

/// Draws the dimmed backdrop, the selection, and the size readout.
final class CaptureOverlayView: NSView {
    var onFinish: ((CaptureOverlayResult) -> Void)?

    private let mode: CaptureOverlayMode
    private let screen: NSScreen
    private var selection: SelectionRect?
    private var hoveredWindow: CapturableWindow?
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, mode: CaptureOverlayMode, screen: NSScreen) {
        self.mode = mode
        self.screen = screen
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func resetCursorRects() {
        // Crosshair for a drag, arrow for window picking — the pointer is the
        // only affordance the overlay has room for.
        switch mode {
        case .area, .measure:
            addCursorRect(bounds, cursor: .crosshair)
        case .window:
            addCursorRect(bounds, cursor: .arrow)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        guard case .window(let candidates) = mode else { return }
        let global = globalPoint(from: event)
        // Front-most first: `capturableWindows()` preserves ScreenCaptureKit's
        // ordering, so the first hit is the window actually on top.
        let hit = candidates.first { $0.frame.contains(global) }
        if hit?.id != hoveredWindow?.id {
            hoveredWindow = hit
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        switch mode {
        case .area, .measure:
            let point = convert(event.locationInWindow, from: nil)
            selection = SelectionRect(origin: point, current: point)
            needsDisplay = true
        case .window:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard selection != nil else { return }
        selection?.current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch mode {
        case .window:
            if let hoveredWindow {
                onFinish?(.window(hoveredWindow))
            } else {
                // Clicking empty desktop cancels rather than capturing
                // something arbitrary.
                onFinish?(.cancelled)
            }

        case .area, .measure:
            guard let selection, selection.isUsable else {
                onFinish?(.cancelled)
                return
            }
            let global = globalRect(from: selection.rect)
            if case .measure = mode {
                onFinish?(.measured(global))
            } else {
                onFinish?(.area(rect: global, screen: screen))
            }
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Dim everything, then knock the highlighted region back out so the
        // user can still see exactly what they are about to capture.
        context.setFillColor(NSColor.black.withAlphaComponent(0.28).cgColor)
        context.fill(bounds)

        guard let highlight = highlightRect else { return }
        context.setBlendMode(.destinationOut)
        context.fill(highlight)
        context.setBlendMode(.normal)

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1)
        context.stroke(highlight.insetBy(dx: 0.5, dy: 0.5))

        drawSizeLabel(for: highlight, in: context)
    }

    private var highlightRect: CGRect? {
        switch mode {
        case .window:
            guard let hoveredWindow else { return nil }
            return localRect(from: hoveredWindow.frame)
        case .area, .measure:
            guard let selection, selection.rect.width > 0 || selection.rect.height > 0 else { return nil }
            return selection.rect
        }
    }

    private func drawSizeLabel(for rect: CGRect, in context: CGContext) {
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 5

        // Prefer just below the selection; flip above when that would run off
        // the bottom of the screen.
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - padding * 2 - 4)
        if origin.y < 4 { origin.y = rect.maxY + 4 }
        origin.x = min(max(4, origin.x), bounds.maxX - size.width - padding * 2 - 4)

        let box = CGRect(
            x: origin.x, y: origin.y,
            width: size.width + padding * 2,
            height: size.height + padding * 2
        )
        context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        context.fill(box)
        (text as NSString).draw(at: CGPoint(x: box.minX + padding, y: box.minY + padding), withAttributes: attributes)
    }

    // MARK: - Coordinates

    /// The overlay covers exactly one screen, so view-local and global
    /// coordinates differ only by that screen's origin.
    private func globalPoint(from event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x + screen.frame.minX, y: local.y + screen.frame.minY)
    }

    private func globalRect(from rect: CGRect) -> CGRect {
        rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }

    private func localRect(from rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    }
}
