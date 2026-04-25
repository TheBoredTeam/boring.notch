//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
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
                NavigationLink(value: "OSD") {
                    Label("OSD", systemImage: "dial.medium.fill")
                }
                NavigationLink(value: "Battery") {
                    Label("Battery", systemImage: "battery.100.bolt")
                }
                NavigationLink(value: "Clipboard") {
                    Label("Clipboard", systemImage: "clipboard")
                }
                NavigationLink(value: "Bluetooth") {
                    Label("Bluetooth", systemImage: "earbuds")
                }
                NavigationLink(value: "SystemStats") {
                    Label("System Stats", systemImage: "cpu")
                }
                NavigationLink(value: "Shelf") {
                    Label("Shelf", systemImage: "books.vertical")
                }
                NavigationLink(value: "Mirror") {
                    Label("Mirror", systemImage: "camera")
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
                case "OSD":
                    OSDSettings()
                case "Battery":
                    Charge()
                case "Clipboard":
                    ClipboardSettings()
                case "Bluetooth":
                    BluetoothSettings()
                case "SystemStats":
                    SystemStatsSettings()
                case "Shelf":
                    Shelf()
                case "Mirror":
                    MirrorSettings()
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

struct ClipboardSettings: View {
    @Default(.enableClipboardHistory) var enableClipboardHistory
    @Default(.clipboardHistorySize) var clipboardHistorySize

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableClipboardHistory) {
                    Text("Enable clipboard history")
                }
            } header: {
                Text("General")
            } footer: {
                Text(
                    "Monitors your clipboard and keeps a history of copied items. Click an item to copy it back — then paste with Cmd+V."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Picker("History size", selection: $clipboardHistorySize) {
                    Text("25 items").tag(25)
                    Text("50 items").tag(50)
                    Text("100 items").tag(100)
                }
            } header: {
                Text("Storage")
            } footer: {
                Text(
                    "Clipboard history is stored in memory only and clears when the app restarts. Pinned items are preserved."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Clipboard")
    }
}

struct BluetoothSettings: View {
    @Default(.showBluetoothBattery) var showBluetoothBattery
    @ObservedObject var btManager = BluetoothBatteryManager.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBluetoothBattery) {
                    Text("Show Bluetooth device battery")
                }
            } header: {
                Text("General")
            } footer: {
                Text(
                    "Shows battery level for connected Bluetooth devices (headphones, earbuds, keyboards, mice) in the notch header."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                if btManager.devices.isEmpty {
                    Text("No connected Bluetooth devices")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(btManager.devices) { device in
                        HStack {
                            Image(systemName: device.deviceType.icon)
                                .frame(width: 20)
                            Text(device.name)
                            Spacer()
                            if device.batteryLevel >= 0 {
                                Text("\(device.batteryLevel)%")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("N/A")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                Button("Refresh") {
                    btManager.refreshDevices()
                }
            } header: {
                Text("Connected Devices")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Bluetooth")
        .onAppear {
            btManager.refreshDevices()
        }
    }
}

struct SystemStatsSettings: View {
    @Default(.showSystemStats) var showSystemStats

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showSystemStats) {
                    Text("Show system stats in notch")
                }
            } header: {
                Text("General")
            } footer: {
                Text(
                    "Displays CPU usage, RAM usage, and thermal state as compact indicators in the notch header. Useful for monitoring performance on MacBook Air (no fan)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("System Stats")
    }
}
