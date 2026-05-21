import Foundation

struct WindowHistoryEntry {
    let restoreFrame: CGRect
    var lastAction: WindowAction
}

@MainActor
final class WindowHistoryStore {
    private var entries: [String: WindowHistoryEntry] = [:]

    func entry(for window: FocusedWindow) -> WindowHistoryEntry? {
        entries[window.identity]
    }

    func ensureRestoreFrame(for window: FocusedWindow, action: WindowAction) {
        if entries[window.identity] == nil {
            entries[window.identity] = WindowHistoryEntry(restoreFrame: window.normalFrame, lastAction: action)
        } else {
            entries[window.identity]?.lastAction = action
        }
    }

    func updateLastAction(_ action: WindowAction, for window: FocusedWindow) {
        if entries[window.identity] == nil {
            entries[window.identity] = WindowHistoryEntry(restoreFrame: window.normalFrame, lastAction: action)
        } else {
            entries[window.identity]?.lastAction = action
        }
    }

    func clear(for window: FocusedWindow) {
        entries.removeValue(forKey: window.identity)
    }
}
