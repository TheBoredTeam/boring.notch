import Foundation
import AppKit

/// Lightweight summary of a window visible on a given display — used by the stage strip.
struct WindowSummary: Identifiable, Equatable {
    let id: String
    let pid: pid_t
    let windowID: CGWindowID?
    let appName: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let title: String?
    let normalFrame: CGRect
    let currentAction: WindowAction?

    static func == (lhs: WindowSummary, rhs: WindowSummary) -> Bool {
        lhs.id == rhs.id
            && lhs.pid == rhs.pid
            && lhs.windowID == rhs.windowID
            && lhs.appName == rhs.appName
            && lhs.title == rhs.title
            && lhs.normalFrame.equalTo(rhs.normalFrame)
            && lhs.currentAction == rhs.currentAction
    }
}

@MainActor
final class WindowPowerState: ObservableObject {
    enum StatusKind {
        case idle
        case success
        case warning
        case error
    }

    @Published var title: String = "Windows"
    @Published var detail: String = "Use shortcuts to move the focused window."
    @Published var appName: String?
    @Published var windowTitle: String?
    @Published var displayName: String?
    @Published var lastAction: WindowAction?
    @Published var preview: WindowLayoutPreview = .neutral
    @Published var statusKind: StatusKind = .idle
    @Published var isAccessibilityAuthorized: Bool = AXIsProcessTrusted()
    @Published var windows: [WindowSummary] = []
    @Published var focusedWindowID: String?

    /// Legacy singleton; each `GojoViewModel` owns its own instance for per-display UI.
    static let shared = WindowPowerState()

    init() {}

    func setIdle() {
        title = "Windows"
        detail = "Use shortcuts to move the focused window."
        preview = .neutral
        statusKind = .idle
        lastAction = nil
    }

    func setFocusedWindow(_ window: FocusedWindow) {
        appName = window.appName
        windowTitle = window.title
        displayName = window.screen.localizedName
        lastAction = WindowGeometryCalculator().matchingAction(for: window)
        title = window.appName
        detail = window.title ?? ""
        statusKind = .idle
        preview = lastAction.map(WindowLayoutPreview.init(action:)) ?? .neutral
    }

    func setNoWindow() {
        title = "No window"
        detail = "Focus an app on this display"
        appName = nil
        windowTitle = nil
        displayName = nil
        lastAction = nil
        preview = .neutral
        statusKind = .warning
    }

    func setPermissionMissing() {
        title = "Accessibility access needed"
        detail = "Open Settings to let Gojo move other app windows."
        appName = nil
        windowTitle = nil
        displayName = nil
        lastAction = nil
        preview = .error
        statusKind = .error
        isAccessibilityAuthorized = false
    }

    func setFailure(_ message: String, detail failureDetail: String) {
        title = message
        detail = failureDetail
        preview = .error
        statusKind = .error
    }

    func setSuccess(action: WindowAction, window: FocusedWindow, restored: Bool = false, constrained: Bool = false) {
        appName = window.appName
        windowTitle = window.title
        displayName = window.screen.localizedName
        lastAction = action
        preview = WindowLayoutPreview(action: action)
        statusKind = constrained ? .warning : .success
        title = window.appName
        detail = window.title ?? (restored ? "Restored" : action.shortLabel)
    }
}
