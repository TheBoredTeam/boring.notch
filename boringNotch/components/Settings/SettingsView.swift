//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Sparkle
import SwiftUI
import SwiftUIIntrospect

private enum SettingsSidebarLayout {
    static let assetTabIconLength: CGFloat = 16
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case media
    case calendar
    case osd
    case battery
    case bluetooth
    case shelf
    case mirror
    case shortcuts
    case advanced
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .media: "Media"
        case .calendar: "Calendar"
        case .osd: "OSD"
        case .battery: "Battery"
        case .bluetooth: "Bluetooth"
        case .shelf: "Shelf"
        case .mirror: "Mirror"
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .appearance: "eye"
        case .media: "play.laptopcomputer"
        case .calendar: "calendar"
        case .osd: "dial.medium.fill"
        case .battery: "battery.100.bolt"
        case .bluetooth: "circle"
        case .shelf: "books.vertical"
        case .mirror: "camera"
        case .shortcuts: "keyboard"
        case .advanced: "gearshape.2"
        case .about: "info.circle"
        }
    }
    
    var resourceImage: String? {
        switch self {
        case .bluetooth: return "bluetooth"
        default: return nil
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    if let assetImageName = tab.resourceImage {
                        Label {
                            Text(tab.title)
                        } icon: {
                            Image(assetImageName)
                                .resizable()
                                .renderingMode(.template)
                                .aspectRatio(contentMode: .fit)
                                .frame(
                                    width: SettingsSidebarLayout.assetTabIconLength,
                                    height: SettingsSidebarLayout.assetTabIconLength
                                )
                        }
                        .tag(tab)
                    } else {
                        Label(tab.title, systemImage: tab.systemImage)
                            .tag(tab)
                    }
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
                case .appearance:
                    Appearance()
                case .media:
                    Media()
                case .calendar:
                    CalendarSettings()
                case .osd:
                    OSDSettings()
                case .battery:
                    Charge()
                case .bluetooth:
                    BluetoothSettings()
                case .shelf:
                    Shelf()
                case .mirror:
                    MirrorSettings()
                case .shortcuts:
                    Shortcuts()
                case .advanced:
                    Advanced()
                case .about:
                    if let controller = updaterController {
                        About(updaterController: controller)
                    } else {
                        // Fallback with a default controller
                        About(
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

