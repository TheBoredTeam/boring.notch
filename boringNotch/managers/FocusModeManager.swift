import Defaults
import Foundation

final class FocusModeManager: ObservableObject {
    static let shared = FocusModeManager()

    @Published var currentFocusName: String?

    private var observer: Any?

    private init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.notificationcenter.focusmode.changed"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshFocusState()
        }
        refreshFocusState()
    }

    /// Reads the active focus mode name from macOS preferences
    func refreshFocusState() {
        let previous = currentFocusName
        guard let dndData = UserDefaults(suiteName: "com.apple.ncprefs")?.data(forKey: "dnd_prefs") else {
            DispatchQueue.main.async { self.currentFocusName = nil }
            return
        }
        guard let dndDict = try? PropertyListSerialization.propertyList(
            from: dndData, options: [], format: nil
        ) as? [String: Any] else {
            DispatchQueue.main.async { self.currentFocusName = nil }
            return
        }

        if let userPrefs = dndDict["userPref"] as? [String: Any],
           let enabled = userPrefs["enabled"] as? Int, enabled == 1 {
            // Try to get the active focus mode name
            let name = dndDict["displayName"] as? String
                ?? userPrefs["modeName"] as? String
                ?? "Focus"
            DispatchQueue.main.async {
                self.currentFocusName = name
                // Post notification when focus mode changes
                if name != previous {
                    NotificationCenter.default.post(
                        name: Notification.Name("FocusModeChanged"),
                        object: nil,
                        userInfo: ["name": name]
                    )
                }
            }
        } else {
            DispatchQueue.main.async {
                self.currentFocusName = nil
                // Post notification when focus mode is disabled
                if previous != nil {
                    NotificationCenter.default.post(
                        name: Notification.Name("FocusModeChanged"),
                        object: nil,
                        userInfo: ["name": "Off"]
                    )
                }
            }
        }
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }
}
