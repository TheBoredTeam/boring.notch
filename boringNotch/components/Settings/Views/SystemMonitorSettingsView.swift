//
//  SystemMonitorSettingsView.swift
//  boringNotch
//
//  Created by Zaky Syihab Hatmoko on 05/03/2026.
//

import Defaults
import SwiftUI

struct SystemMonitorSettings: View {
    @ObservedObject var monitor = SystemMonitorManager.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showSystemMonitor) {
                    Text("Show system monitor")
                }
            } header: {
                Text("General")
            } footer: {
                Text("Display CPU and memory usage indicators in the notch header area, next to the battery indicator.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if Defaults[.showSystemMonitor] {
                Section {
                    HStack {
                        Text("CPU Usage")
                        Spacer()
                        Text(String(format: "%.1f%%", monitor.cpuUsage))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Memory Used")
                        Spacer()
                        Text(String(format: "%.1f / %.0f GB", monitor.memoryUsed, monitor.memoryTotal))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Current Stats")
                } footer: {
                    Text("Statistics update every 3 seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("System Monitor")
    }
}
