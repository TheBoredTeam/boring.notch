//
//  ClaudeUsageSettings.swift
//  boringNotch
//
//  Settings panel for AI usage widget
//

import SwiftUI
import Defaults

struct ClaudeUsageSettings: View {
    @ObservedObject var vm = ClaudeUsageViewModel.shared

    var body: some View {
        Form {
            Defaults.Toggle(key: .showClaudeUsage) {
                Text("Show AI usage in notch")
            }
            Defaults.Toggle(key: .showClaudeUsageLiveActivity) {
                Text("Always show AI usage in closed notch")
            }
            .disabled(!Defaults[.showClaudeUsage])

            Section(header: Text("Current Usage")) {
                if vm.providers.isEmpty {
                    Text("No data available")
                        .foregroundColor(.secondary)
                    Text("Install claude-usage CLI to feed Claude and Codex data: curl -fsSL https://raw.githubusercontent.com/Dede98/claude-usage/main/install.sh | bash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(vm.providers) { provider in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(provider.name)
                                    .fontWeight(.semibold)
                                Spacer()
                                if let plan = provider.planLabel {
                                    Text(plan)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if let errorText = provider.errorText {
                                Text(errorText)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else {
                                ForEach(provider.meters) { meter in
                                    HStack {
                                        Text(meter.label)
                                        Spacer()
                                        Text(meter.kind == .remaining ? "\(meter.utilization)% left" : "\(meter.utilization)%")
                                            .foregroundColor(meterColor(meter))
                                            .fontWeight(.semibold)
                                        if let reset = meter.resetsIn {
                                            Text("resets in \(reset)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }

                            if let statusText = provider.statusText {
                                Text(statusText)
                                    .font(.caption)
                                    .foregroundColor(provider.statusLevel == .critical ? .red : .orange)
                            }

                            if let credits = provider.creditsLabel {
                                Text(credits)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section(header: Text("Setup")) {
                Text("This widget reads ~/.claude/usage-data.json from the claude-usage CLI. Current schema support includes multi-provider snapshots with Claude and Codex.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if vm.isStale {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Data is stale. Make sure the claude-usage daemon is running.")
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

    private func meterColor(_ meter: UsageMeterDisplay) -> Color {
        if meter.kind == .remaining {
            if meter.utilization <= 10 { return .red }
            if meter.utilization <= 25 { return .orange }
            return .green
        }

        if meter.utilization >= 90 { return .red }
        if meter.utilization >= 75 { return .orange }
        return .green
    }
}
