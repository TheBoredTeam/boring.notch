//
//  ClaudeUsageSettings.swift
//  boringNotch
//
//  Settings panel for Claude usage widget
//

import SwiftUI
import Defaults

struct ClaudeUsageSettings: View {
    @ObservedObject var vm = ClaudeUsageViewModel.shared

    var body: some View {
        Form {
            Defaults.Toggle(key: .showClaudeUsage) {
                Text("Show Claude usage in notch")
            }

            Section(header: Text("Current Usage")) {
                if vm.meters.isEmpty {
                    Text("No data available")
                        .foregroundColor(.secondary)
                    Text("Install the Claude Usage Monitor Chrome extension to feed data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(vm.meters) { meter in
                        HStack {
                            Text(meter.label)
                            Spacer()
                            Text("\(meter.utilization)%")
                                .foregroundColor(meterColor(meter.utilization))
                                .fontWeight(.semibold)
                            if let reset = meter.resetsIn {
                                Text("resets in \(reset)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if vm.extraUsageEnabled {
                        HStack {
                            Text("Extra usage credits")
                            Spacer()
                            Text(String(format: "$%.2f", vm.extraUsageCredits))
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            Section(header: Text("Setup")) {
                Text("This widget reads from ~/.claude/usage-data.json which is written by the Claude Usage Monitor Chrome extension.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if vm.isStale {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Data is stale. Make sure Chrome is running with the extension.")
                            .font(.caption)
                    }
                } else if let updated = vm.lastUpdated {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Last updated: \(updated, style: .relative) ago")
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func meterColor(_ pct: Int) -> Color {
        if pct > 80 { return .red }
        if pct > 50 { return .orange }
        return .green
    }
}
