//
//  SystemMonitorSettingsView.swift
//  boringNotch
//
//  Controls for the system monitor tab: whether it exists at all, which
//  cards it shows, and how often it samples.
//

import Defaults
import SwiftUI

struct SystemMonitorSettingsView: View {
    @Default(.systemMonitorEnabled) private var enabled
    @Default(.systemMonitorMetrics) private var metrics
    @Default(.systemMonitorRefreshInterval) private var refreshInterval

    /// Offered intervals, in seconds. One second is as fast as it is worth
    /// going — the underlying counters are cheap but not free, and a notch
    /// that updates faster than the eye tracks it just looks unstable.
    private let intervals: [TimeInterval] = [1, 2, 5]

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .systemMonitorEnabled) {
                    Text("Show the system monitor")
                }
            } footer: {
                Text("Adds a System tab to the notch with live CPU, memory, battery, disk, network and Wi-Fi readings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(SystemMetricKind.displayOrder) { metric in
                    Toggle(isOn: binding(for: metric)) {
                        Label(metric.localizedTitle, systemImage: metric.systemImage)
                    }
                }
            } header: {
                Text("Metrics")
            } footer: {
                if metrics.isEmpty {
                    Text("Select at least one metric, or the System tab will be empty.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Cards appear in the notch in the order listed here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!enabled)

            Section {
                Picker("Refresh interval", selection: $refreshInterval) {
                    ForEach(intervals, id: \.self) { interval in
                        Text(intervalLabel(interval)).tag(interval)
                    }
                }

                Defaults.Toggle(key: .systemMonitorInHeader) {
                    Text("Show CPU and memory in the notch header")
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Sampling only runs while the monitor is visible, so a closed notch costs nothing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(
                        """
                        Wi-Fi signal strength and network name come from macOS only when \
                        Location Services is enabled for Boring Notch. Without it, the \
                        Wi-Fi card shows no reading.
                        """
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("System Monitor")
    }

    private func binding(for metric: SystemMetricKind) -> Binding<Bool> {
        Binding(
            get: { metrics.contains(metric) },
            set: { isOn in
                if isOn { metrics.insert(metric) } else { metrics.remove(metric) }
            }
        )
    }

    /// One key per option rather than a "%d seconds" format string: the
    /// catalog has no plural entries yet, and a shared format would render
    /// the 1-second option as "1 seconds".
    private func intervalLabel(_ interval: TimeInterval) -> String {
        switch Int(interval) {
        case 1: return NSLocalizedString("system_monitor_interval_1s", comment: "Refresh interval option: one second")
        case 5: return NSLocalizedString("system_monitor_interval_5s", comment: "Refresh interval option: five seconds")
        default: return NSLocalizedString("system_monitor_interval_2s", comment: "Refresh interval option: two seconds")
        }
    }
}
