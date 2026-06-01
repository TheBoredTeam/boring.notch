//  PermissionsService.swift
//  IslandNotch
//
//  Purpose: Checks/requests the two TCC permissions the app needs and exposes
//           live status for the Settings UI. Everything degrades gracefully.
//  Layer: Service

import ApplicationServices
import CoreGraphics
import Foundation
import Observation

@Observable
final class PermissionsService {
    /// Accessibility — required for the global double-⌘ CGEventTap.
    private(set) var accessibilityGranted: Bool = false
    /// Screen Recording — required to capture screen content.
    private(set) var screenRecordingGranted: Bool = false
    /// Ad-hoc signed builds get a new identity every rebuild; TCC grants stop matching.
    private(set) var isAdHocSigned: Bool = true
    /// Stable signing authority when not ad-hoc (e.g. Apple Development or local dev cert).
    private(set) var signingAuthority: String?

    init() {
        refresh()
    }

    /// Re-reads both permission states. Call on launch and when a Settings window
    /// becomes active (grants can change while the app runs).
    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        isAdHocSigned = CodeSigningStatus.isAdHocSigned
        signingAuthority = CodeSigningStatus.authoritySummary
        Log.permissions.debug(
            "refresh ax=\(self.accessibilityGranted) screen=\(self.screenRecordingGranted) adhoc=\(self.isAdHocSigned)"
        )
    }

    /// Triggers the system Accessibility prompt (only shows once per identity).
    /// Returns the current trust state synchronously.
    @discardableResult
    func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        accessibilityGranted = trusted
        return trusted
    }

    /// Triggers the system Screen Recording prompt. The grant only takes effect
    /// after the app is relaunched, so we surface that in the UI copy.
    @discardableResult
    func requestScreenRecording() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        screenRecordingGranted = granted
        return granted
    }
}
