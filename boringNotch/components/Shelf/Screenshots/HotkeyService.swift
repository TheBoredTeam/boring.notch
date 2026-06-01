//
//  HotkeyService.swift
//  boringNotch
//
//  Purpose: Registers the configurable global keyboard chord (KeyboardShortcuts)
//           that triggers a capture. This is the de-risked hotkey path that
//           works without Accessibility permission.
//  Layer: Service
//

import Foundation
import KeyboardShortcuts

/// Owns the KeyboardShortcuts registration and forwards activations as a
/// `.chord`-sourced capture request.
final class HotkeyService {
    /// Invoked on the main actor when the chord fires.
    var onCapture: ((CaptureSource) -> Void)?

    func start() {
        KeyboardShortcuts.onKeyUp(for: .captureScreenshot) { [weak self] in
            Log.hotkey.debug("chord activated")
            self?.onCapture?(.chord)
        }
    }
}
