//
//  SystemActivitySettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct SystemActivitySettings: View {
    @Default(.systemActivityEnabled) private var systemActivityEnabled

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
                Text("Only enabled gauges are sampled while the System tab is visible.")
            }
            .disabled(!systemActivityEnabled)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("System Activity")
    }
}

#Preview {
    SystemActivitySettings()
        .frame(width: 500, height: 420)
}
