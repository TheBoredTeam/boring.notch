import AppKit
import Foundation
import KeyboardShortcuts
import os.log

/// Lightweight window-management diagnostics. Capture with:
///   /usr/bin/log stream --predicate 'subsystem == "rohoswagger.gojo"' --style compact
private let gojoMainDebugLog = OSLog(subsystem: "rohoswagger.gojo", category: "debug")
func gojoDebug(_ message: String) {
    os_log("%{public}@", log: gojoMainDebugLog, type: .default, "[GOJO-MAIN] " + message)
}

@MainActor
final class WindowShortcutController {
    static let shared = WindowShortcutController()

    private var registered = false

    private init() {}

    func register() {
        guard !registered else { return }
        registered = true

        KeyboardShortcuts.onKeyDown(for: .windowLeftHalf) { Self.execute(.leftHalf) }
        KeyboardShortcuts.onKeyDown(for: .windowRightHalf) { Self.execute(.rightHalf) }
        KeyboardShortcuts.onKeyDown(for: .windowTopHalf) { Self.execute(.topHalf) }
        KeyboardShortcuts.onKeyDown(for: .windowBottomHalf) { Self.execute(.bottomHalf) }
        KeyboardShortcuts.onKeyDown(for: .windowMaximize) { Self.execute(.maximize) }
        KeyboardShortcuts.onKeyDown(for: .windowZoom) { Self.execute(.zoom) }
    }

    private static func execute(_ action: WindowAction) {
        Task { @MainActor in
            let context = WindowPowerSession.contextForMouseLocation()
            gojoDebug("keybind \(action): mouse=\(NSEvent.mouseLocation) → screenUUID=\(context.screenUUID ?? "nil")")
            await WindowActionExecutor.shared.execute(
                action,
                screenUUID: context.screenUUID,
                state: context.state
            )
        }
    }
}
