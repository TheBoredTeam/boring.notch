//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Sparkle
import SwiftUI
import SwiftUIIntrospect

private enum SettingsTab: String, CaseIterable, Hashable {
    case general
    case appearance
    case media
    case calendar
    case weather
    case osd
    case battery
    case shelf
    case shortcuts
    case advanced
    case about
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab? = .general
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: SettingsTab.general) {
                    Label("General", systemImage: "gear")
                }
                NavigationLink(value: SettingsTab.appearance) {
                    Label("Appearance", systemImage: "eye")
                }
                NavigationLink(value: SettingsTab.media) {
                    Label("Media", systemImage: "play.laptopcomputer")
                }
                NavigationLink(value: SettingsTab.calendar) {
                    Label("Calendar", systemImage: "calendar")
                }
                NavigationLink(value: SettingsTab.weather) {
                    Label("Weather", systemImage: "cloud.sun")
                }
                NavigationLink(value: SettingsTab.osd) {
                    Label("OSD", systemImage: "dial.medium.fill")
                }
                NavigationLink(value: SettingsTab.battery) {
                    Label("Battery", systemImage: "battery.100.bolt")
                }
                NavigationLink(value: SettingsTab.shelf) {
                    Label("Shelf", systemImage: "books.vertical")
                }
                NavigationLink(value: SettingsTab.shortcuts) {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                NavigationLink(value: SettingsTab.advanced) {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                NavigationLink(value: SettingsTab.about) {
                    Label("About", systemImage: "info.circle")
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
                case .weather:
                    WeatherSettings()
                case .osd:
                    OSDSettings()
                case .battery:
                    Charge()
                case .shelf:
                    Shelf()
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
                default:
                    GeneralSettings()
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
