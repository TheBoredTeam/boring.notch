//
//  SettingsTab.swift
//  boringNotch
//

import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case notch
    case appearance
    case media
    case calendar
    case shelf
    case mirror
    case battery
    case osd
    case notifications
    case shortcuts
    case about

    enum Icon {
        case system(String)
        case custom(String)
    }

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .general: "General"
        case .notch: "Notch"
        case .appearance: "Appearance"
        case .media: "Media"
        case .calendar: "Calendar"
        case .shelf: "Shelf"
        case .mirror: "Mirror"
        case .battery: "Battery"
        case .osd: "OSD"
        case .notifications: "Notifications"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }

    var icon: Icon {
        switch self {
        case .general: .system("gear")
        case .notch: .custom("notch")
        case .appearance: .system("paintbrush")
        case .media: .system("play.rectangle")
        case .calendar: .system("calendar")
        case .shelf: .system("tray.and.arrow.down")
        case .mirror: .system("video")
        case .battery: .system("battery.100.bolt")
        case .osd: .system("dial.medium.fill")
        case .notifications: .system("bell.badge")
        case .shortcuts: .system("keyboard")
        case .about: .system("info.circle")
        }
    }
}

struct SettingsTabLabel: View {
    let tab: SettingsTab

    var body: some View {
        Label {
            Text(tab.title)
        } icon: {
            switch tab.icon {
            case .system(let imageName):
                Image(systemName: imageName)

            case .custom(let imageName):
                Image(imageName)
            }
        }
    }
}
