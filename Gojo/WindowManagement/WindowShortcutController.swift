import Foundation
import KeyboardShortcuts

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
    }

    private static func execute(_ action: WindowAction) {
        Task { @MainActor in
            let context = WindowPowerSession.contextForMouseLocation()
            await WindowActionExecutor.shared.execute(
                action,
                screenUUID: context.screenUUID,
                state: context.state
            )
        }
    }
}
