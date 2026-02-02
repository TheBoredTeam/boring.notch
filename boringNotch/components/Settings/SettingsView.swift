//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    @State private var selectedTab = "General"
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "General") {
                    Label("General", systemImage: "gear")
                }
                NavigationLink(value: "Appearance") {
                    Label("Appearance", systemImage: "eye")
                }
                NavigationLink(value: "Media") {
                    Label("Media", systemImage: "play.laptopcomputer")
                }
                NavigationLink(value: "Calendar") {
                    Label("Calendar", systemImage: "calendar")
                }
                NavigationLink(value: "HUD") {
                    Label("HUDs", systemImage: "dial.medium.fill")
                }
                NavigationLink(value: "Battery") {
                    Label("Battery", systemImage: "battery.100.bolt")
                }
                NavigationLink(value: "Shelf") {
                    Label("Shelf", systemImage: "books.vertical")
                }
                NavigationLink(value: "Shortcuts") {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                NavigationLink(value: "Advanced") {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                NavigationLink(value: "About") {
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
                case "General":
                    GeneralSettings()
                case "Appearance":
                    Appearance()
                case "Media":
                    Media()
                case "Calendar":
                    CalendarSettings()
                case "HUD":
                    HUD()
                case "Battery":
                    Charge()
                case "Shelf":
                    Shelf()
                case "Shortcuts":
                    Shortcuts()
                case "Advanced":
                    Advanced()
                case "About":
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

#Preview {
    HUD()
}
