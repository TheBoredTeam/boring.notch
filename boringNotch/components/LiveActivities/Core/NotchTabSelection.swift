// SPDX-License-Identifier: GPL-3.0-only

enum NotchViews: Hashable {
    case home
    case shelf
    case extensionTab(ExtensionTabID)

    /// Registration never steals selection. Removing or disabling the selected
    /// extension returns to Home while built-in selections remain untouched.
    func reconciled(availableExtensionTabs: Set<ExtensionTabID>) -> Self {
        if case .extensionTab(let id) = self, !availableExtensionTabs.contains(id) {
            return .home
        }
        return self
    }
}
