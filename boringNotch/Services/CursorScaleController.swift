//
//  CursorScaleController.swift
//  boringNotch
//

import AppKit
import Defaults
import KeyboardShortcuts

@MainActor
final class CursorScaleController {
    static let shared = CursorScaleController()

    private typealias UACursorSetScale = @convention(c) (Double) -> Void
    private typealias UACursorGetScale = @convention(c) () -> Double

    private enum State {
        case inactive
        case timedActive(originalScale: Double, token: UUID)
        case toggleActive(originalScale: Double)
    }

    private let setScale: UACursorSetScale?
    private let getScale: UACursorGetScale?
    private var state: State = .inactive
    private var restoreTimer: Timer?
    private var isShortcutHeld = false

    var isAvailable: Bool {
        setScale != nil
    }

    private init() {
        let functions = Self.loadCursorScaleFunctions()
        setScale = functions?.setScale
        getScale = functions?.getScale
    }

    func registerShortcut() {
        KeyboardShortcuts.onKeyDown(for: .cursorScale) { [weak self] in
            Task { @MainActor in
                self?.handleShortcutDown()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .cursorScale) { [weak self] in
            Task { @MainActor in
                self?.handleShortcutUp()
            }
        }
    }

    func handleShortcutDown() {
        guard isAvailable else { return }
        guard !isShortcutHeld else { return }
        isShortcutHeld = true

        switch Defaults[.cursorScaleActivationMode] {
        case .timed:
            startTimed()
        case .toggle:
            toggle()
        }
    }

    func handleShortcutUp() {
        isShortcutHeld = false
    }

    func restore() {
        restoreTimer?.invalidate()
        restoreTimer = nil

        switch state {
        case .inactive:
            return
        case .timedActive(let originalScale, _), .toggleActive(let originalScale):
            setScale?(originalScale)
            state = .inactive
        }
    }

    private func startTimed() {
        let originalScale = currentOriginalScale()
        let token = UUID()

        restoreTimer?.invalidate()
        setScale?(clampedCursorScale)
        state = .timedActive(originalScale: originalScale, token: token)

        restoreTimer = Timer.scheduledTimer(withTimeInterval: clampedDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.restoreTimed(token: token)
            }
        }
    }

    private func toggle() {
        restoreTimer?.invalidate()
        restoreTimer = nil

        switch state {
        case .toggleActive:
            restore()
        case .inactive, .timedActive:
            let originalScale = currentOriginalScale()
            setScale?(clampedCursorScale)
            state = .toggleActive(originalScale: originalScale)
        }
    }

    private func restoreTimed(token: UUID) {
        guard case .timedActive(let originalScale, let activeToken) = state, activeToken == token else {
            return
        }

        restoreTimer?.invalidate()
        restoreTimer = nil
        setScale?(originalScale)
        state = .inactive
    }

    private func currentOriginalScale() -> Double {
        switch state {
        case .inactive:
            return normalizedScale(getScale?() ?? 1.0)
        case .timedActive(let originalScale, _), .toggleActive(let originalScale):
            return originalScale
        }
    }

    private var clampedDuration: TimeInterval {
        min(max(Defaults[.cursorScaleDuration], 0.5), 30)
    }

    private var clampedCursorScale: Double {
        min(max(Defaults[.cursorScaleAmount], 1.5), 8)
    }

    private func normalizedScale(_ scale: Double) -> Double {
        guard scale.isFinite, scale > 0 else { return 1.0 }
        return scale
    }

    private static func loadCursorScaleFunctions() -> (setScale: UACursorSetScale, getScale: UACursorGetScale?)? {
        let candidates = [
            "/System/Library/PrivateFrameworks/UniversalAccess.framework/Versions/A/UniversalAccess",
            "/usr/lib/libUniversalAccess.dylib",
            "/System/Library/PrivateFrameworks/UniversalAccess.framework/Versions/A/Libraries/libUAPreferences.dylib",
            "/System/Library/PrivateFrameworks/UniversalAccess.framework/Versions/A/Frameworks/UniversalAccessCore.framework/Versions/A/UniversalAccessCore",
        ]

        for path in candidates {
            guard let handle = dlopen(path, RTLD_NOW) else { continue }

            let getScale = ["UACursorGetScale", "_UACursorGetScale"].compactMap { symbol -> UACursorGetScale? in
                guard let pointer = dlsym(handle, symbol) else { return nil }
                return unsafeBitCast(pointer, to: UACursorGetScale.self)
            }.first

            for symbol in ["UACursorSetScale", "_UACursorSetScale"] {
                guard let pointer = dlsym(handle, symbol) else { continue }
                return (unsafeBitCast(pointer, to: UACursorSetScale.self), getScale)
            }
        }

        return nil
    }
}
