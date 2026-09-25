//
//  SystemActivitySettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct SystemActivitySettings: View {
    @Default(.systemActivityEnabled) private var systemActivityEnabled
    @Default(.showSystemActivityInMainCard) private var showInMainCard
    @Default(.showCalendar) private var showCalendar

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .systemActivityEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show system activity")
                        Text("Adds the System tab to the notch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Defaults.Toggle(key: .showSystemActivityInMainCard) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show in main card")
                        if showCalendar {
                            Text("Turn off Show calendar in Calendar settings first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Shows compact gauges beside the media controls.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!systemActivityEnabled || showCalendar)
            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .showCPUActivityGauge) {
                    Label("CPU usage", systemImage: "cpu")
                }
                Defaults.Toggle(key: .showGPUActivityGauge) {
                    Label("GPU usage", systemImage: "rectangle.3.group")
                }
                Defaults.Toggle(key: .showMemoryActivityGauge) {
                    Label("Memory usage", systemImage: "memorychip")
                }
                Defaults.Toggle(key: .showCPUTemperatureGauge) {
                    Label("CPU temperature", systemImage: "thermometer.medium")
                }
            } header: {
                Text("Visible gauges")
            } footer: {
                Text("Only enabled gauges are sampled while a System Activity view is visible.")
            }
            .disabled(!systemActivityEnabled)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("System Activity")
        .onChange(of: systemActivityEnabled) { _, enabled in
            if !enabled {
                showInMainCard = false
            }
        }
    }
}

#Preview {
    SystemActivitySettings()
        .frame(width: 500, height: 420)
}
