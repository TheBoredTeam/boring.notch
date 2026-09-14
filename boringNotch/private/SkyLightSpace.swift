//
//  SkyLightSpace.swift
//  boringNotch
//
//  The single place window↔space membership is decided.
//

import AppKit
import SkyLightWindow

/// Which of the app's spaces a window belongs to.
///
/// The app owns two: `NotchSpaceManager.notchSpace` (a `CGSSpace` at absolute level
/// `Int32.max`, used during a normal session) and `SkyLightOperator.shared.space` (absolute
/// level 400, `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`, the only level in this
/// codebase that composites above the lock screen).
enum WindowSpaceMembership {
    case notch
    case skyLight
    /// In neither space. Use before closing a window.
    case none
}

/// Move a window between the app's spaces, keeping `CGSSpace.windows` honest.
///
/// ## Why the ordering matters
///
/// `CGSSpace.windows` is a *cached* `Set<NSWindow>` whose `didSet` issues CGS calls only for
/// the diff against the previous value. SkyLight's add is
/// `SLSSpaceAddWindowsAndRemoveFromSpaces(…, 7)`, where the mask evicts the window from every
/// other space — behind that cache's back. So delegating without removing first leaves the
/// cache claiming a membership the WindowServer has already dropped, and a later `insert`
/// produces an empty diff and issues no call at all. The window then belongs to *no* space
/// and never renders again.
///
/// Removing through the set before delegating is the whole fix.
@MainActor
func setWindowSpace(_ window: NSWindow, to target: WindowSpaceMembership) {
    let notchSpace = NotchSpaceManager.shared.notchSpace

    switch target {
    case .skyLight:
        notchSpace.windows.remove(window)
        SkyLightOperator.shared.delegateWindowLogged(window)
    case .notch:
        SkyLightOperator.shared.undelegateWindow(window)
        notchSpace.windows.insert(window)
    case .none:
        notchSpace.windows.remove(window)
        SkyLightOperator.shared.undelegateWindow(window)
    }
}

extension SkyLightOperator {
    /// Loads a SkyLight symbol. The framework is already resident in every AppKit process, so
    /// this is a lookup rather than a real load.
    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW
        ), let pointer = dlsym(handle, name) else {
            NSLog("🪟 SkyLight symbol \(name) unavailable")
            return nil
        }
        return unsafeBitCast(pointer, to: type)
    }

    /// The package's own `delegateWindow` throws the `CGError` away, which is why failures in
    /// this subsystem have always been invisible. This is the same call with the result read.
    func delegateWindowLogged(_ window: NSWindow) {
        typealias Add = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
        guard let add = Self.symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: Add?.self) ?? nil
        else {
            // Fall back to the package's version rather than silently doing nothing.
            delegateWindow(window)
            return
        }

        // The 7 is an undocumented "remove from all space types" mask.
        let result = add(connection, space, [window.windowNumber] as CFArray, 7)
        if result != 0 {
            NSLog("🪟 SLSSpaceAddWindowsAndRemoveFromSpaces failed: \(result)")
        }
    }

    /// v1.0.0 of the package has no removal call, so this supplies one.
    func undelegateWindow(_ window: NSWindow) {
        typealias Remove = @convention(c) (Int32, CFArray, CFArray) -> Int32
        guard let remove = Self.symbol("SLSRemoveWindowsFromSpaces", as: Remove?.self) ?? nil
        else { return }

        let result = remove(connection, [window.windowNumber] as CFArray, [space] as CFArray)
        if result != 0 {
            NSLog("🪟 SLSRemoveWindowsFromSpaces failed: \(result)")
        }
    }
}
