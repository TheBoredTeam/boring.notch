//
//  SettingsSidebarItem.swift
//  boringNotch
//

import Foundation

// Tabs and search results share one selection type so they can be rows of the same `List`.
// With one list, the sidebar is never rebuilt when a search starts or ends.
enum SettingsSidebarItem: Hashable {
    case tab(SettingsTab)
    case entry(String)
}
