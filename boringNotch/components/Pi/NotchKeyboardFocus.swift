//
//  NotchKeyboardFocus.swift
//  boringNotch
//
//  Lets text fields inside the non-activating notch panel receive keyboard input.
//

import AppKit
import SwiftUI

/// Accepts the first click on a non-key panel so controls focus immediately.
private final class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct FirstMouseSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FirstMouseView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Makes the hosting notch window key while text input is active.
private struct NotchWindowKeySurface: NSViewRepresentable {
    let wantsKey: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        if wantsKey, window.canBecomeKey {
            window.makeKey()
        } else if !wantsKey, window.isKeyWindow {
            window.resignKey()
        }
    }
}

extension View {
    /// First click reaches SwiftUI controls on the non-activating notch panel.
    func notchAcceptsFirstMouse() -> some View {
        background(FirstMouseSurface().allowsHitTesting(false))
    }

    /// Promote/demote key-window status for embedded text fields.
    func notchKeyboardFocus(_ active: Bool) -> some View {
        background(NotchWindowKeySurface(wantsKey: active).allowsHitTesting(false))
    }
}
