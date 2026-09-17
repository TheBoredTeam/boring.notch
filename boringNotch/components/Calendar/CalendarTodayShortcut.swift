//
//  CalendarTodayShortcut.swift
//  boringNotch
//
//  Calendar timeline and month presentation.
//

import AppKit
import SwiftUI

@MainActor
protocol CalendarKeyboardFocusProviding: AnyObject {
    var wantsKeyForTextInput: Bool { get }
    func setCalendarFocus(_ requested: Bool, owner: AnyObject)
}

extension View {
    func calendarTodayShortcut(_ action: @escaping () -> Void) -> some View {
        background(CalendarTodayKeyHandler(action: action))
    }
}

/// The notch is a nonactivating panel, so its calendar needs an explicit key responder.
private struct CalendarTodayKeyHandler: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CalendarTodayKeyView {
        CalendarTodayKeyView(action: action)
    }

    func updateNSView(_ view: CalendarTodayKeyView, context: Context) {
        view.action = action
    }

    static func dismantleNSView(_ view: CalendarTodayKeyView, coordinator: ()) {
        view.removeMonitor()
    }
}

@MainActor
enum CalendarTodayShortcutRouting {
    static func shouldHandle(_ event: NSEvent, in window: NSWindow) -> Bool {
        // ANSI T stays available when another keyboard layout maps it to a different letter.
        guard event.type == .keyDown, event.window === window, window.isKeyWindow,
              (event.keyCode == 17 || event.charactersIgnoringModifiers?.lowercased() == "t"),
              event.modifierFlags.intersection([.command, .control, .option, .function]).isEmpty else { return false }
        if (window as? CalendarKeyboardFocusProviding)?.wantsKeyForTextInput == true { return false }
        if let editor = window.firstResponder as? NSTextView, editor.isEditable { return false }
        return true
    }
}

@MainActor
final class CalendarTodayKeyView: NSView {
    var action: () -> Void
    private var monitor: Any?
    private weak var focusWindow: NSWindow?

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { return nil }
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard let window else { return }
        focusWindow = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalEvent(event)
        }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window, self.monitor != nil else { return }
            // Claim only this panel; the application behind it keeps its place.
            self.claimCalendarFocus(in: window)
        }
    }

    func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard monitor != nil, let window, event.window === window else { return event }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            claimCalendarFocus(in: window)
            return event
        default:
            guard CalendarTodayShortcutRouting.shouldHandle(event, in: window) else { return event }
            if !event.isARepeat { action() }
            return nil
        }
    }

    private func claimCalendarFocus(in window: NSWindow) {
        let focusProvider = window as? CalendarKeyboardFocusProviding
        guard focusProvider?.wantsKeyForTextInput != true else { return }
        focusProvider?.setCalendarFocus(true, owner: self)
        if !window.isKeyWindow { window.makeKey() }
        if let text = window.firstResponder as? NSTextView,
           text.window === window, !text.isEditable, !text.isHiddenOrHasHiddenAncestor { return }
        // Calendar has selectable details, but no editor; an old Clipboard editor must let go.
        window.makeFirstResponder(self)
    }

    func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        let wasFirstResponder = focusWindow?.firstResponder === self
        if wasFirstResponder { focusWindow?.makeFirstResponder(nil) }
        if let provider = focusWindow as? CalendarKeyboardFocusProviding {
            provider.setCalendarFocus(false, owner: self)
        } else if wasFirstResponder {
            focusWindow?.resignKey()
        }
        focusWindow = nil
    }
}
