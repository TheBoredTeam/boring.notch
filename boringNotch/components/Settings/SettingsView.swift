//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Sparkle
import SwiftUI
import SwiftUIIntrospect

private enum SettingsTab: String, CaseIterable, Identifiable {
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

    var id: Self { self }

    var title: String {
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

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .notch: "notch"
        case .appearance: "paintbrush"
        case .media: "play.rectangle"
        case .calendar: "calendar"
        case .shelf: "tray.and.arrow.down"
        case .mirror: "video"
        case .battery: "battery.100.bolt"
        case .osd: "dial.medium.fill"
        case .notifications: "bell.badge"
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?
    let camera: CameraModel

    init(updaterController: SPUStandardUpdaterController? = nil, camera: CameraModel) {
        self.updaterController = updaterController
        self.camera = camera
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettings()
                case .notch:
                    NotchSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .media:
                    MediaSettingsView()
                case .notifications:
                    NotificationSettingsView()
                case .calendar:
                    CalendarSettings()
                case .osd:
                    OSDSettings()
                case .battery:
                    BatterySettingsView()
                case .shelf:
                    ShelfSettingsView()
                case .mirror:
                    WebcamSettingsView(camera: camera)
                case .shortcuts:
                    ShortcutsSettingsView()
                case .about:
                    if let controller = updaterController {
                        AboutView(updaterController: controller)
                    } else {
                        // Fallback with a default controller
                        AboutView(
                            updaterController: SPUStandardUpdaterController(
                                startingUpdater: false, updaterDelegate: nil,
                                userDriverDelegate: nil))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: .accentColorChanged)) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }
}
