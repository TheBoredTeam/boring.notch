//
//  ClaudeCodeStatsView.swift
//  boringNotch
//
//  Compact view showing Claude Code stats - designed to fit in 190px notch height
//

import SwiftUI

struct ClaudeCodeStatsView: View {
    @ObservedObject var manager = ClaudeCodeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Session picker + connection status + model/branch
            HStack(spacing: 6) {
                SessionPicker(manager: manager)

                if manager.state.isConnected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)

                    if !manager.state.model.isEmpty {
                        Text(modelDisplayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if !manager.state.gitBranch.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 8))
                            Text(manager.state.gitBranch)
                                .lineLimit(1)
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            if manager.state.isConnected {
                // Row 2: Context bar with token breakdown
                ContextBarWithBreakdown(
                    percentage: manager.state.contextPercentage,
                    usage: manager.state.tokenUsage
                )

                // Row 3: Todo list (show up to 3)
                if !manager.state.todos.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(manager.state.todos.prefix(3)) { todo in
                            HStack(spacing: 4) {
                                Image(systemName: todoIcon(for: todo.status))
                                    .font(.system(size: 8))
                                    .foregroundColor(todoColor(for: todo.status))
                                Text(todo.content)
                                    .font(.caption2)
                                    .foregroundColor(todo.status == .completed ? .secondary.opacity(0.6) : .secondary)
                                    .lineLimit(1)
                                    .strikethrough(todo.status == .completed)
                                Spacer()
                            }
                        }
                    }
                }

                // Row 4: Last message output
                if !manager.state.lastMessage.isEmpty {
                    Text(manager.state.lastMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Row 5: Active/recent tools
                if !manager.state.activeTools.isEmpty || !manager.state.recentTools.isEmpty {
                    HStack(spacing: 4) {
                        if let activeTool = manager.state.activeTools.first {
                            ToolActivityIndicator(isActive: true, toolName: activeTool.toolName)
                                .scaleEffect(0.5)
                            Text(activeTool.toolName)
                                .font(.caption2)
                                .foregroundColor(.orange)
                        } else if let recentTool = manager.state.recentTools.first {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.green)
                            Text(recentTool.toolName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            if let duration = recentTool.durationMs {
                                Text("\(duration)ms")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }
                        Spacer()
                    }
                }

            } else {
                // Not connected state - centered
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.title3)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("No session selected")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if manager.availableSessions.isEmpty {
                            Text("Start Claude Code to begin")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        } else {
                            Text("\(manager.availableSessions.count) session\(manager.availableSessions.count == 1 ? "" : "s") available")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var modelDisplayName: String {
        if manager.state.model.contains("opus") {
            return "Opus"
        } else if manager.state.model.contains("sonnet") {
            return "Sonnet"
        } else if manager.state.model.contains("haiku") {
            return "Haiku"
        }
        return "Claude"
    }

    private func todoIcon(for status: ClaudeTodoItem.TodoStatus) -> String {
        switch status {
        case .pending:
            return "circle"
        case .inProgress:
            return "circle.lefthalf.filled"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    private func todoColor(for status: ClaudeTodoItem.TodoStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .inProgress:
            return .orange
        case .completed:
            return .green
        }
    }
}

// Context bar with token breakdown
struct ContextBarWithBreakdown: View {
    let percentage: Double
    let usage: TokenUsage

    private var barColor: Color {
        if percentage > 80 { return .red }
        if percentage > 60 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Progress bar row
            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.3))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor)
                            .frame(width: max(0, geo.size.width * min(1, percentage / 100)))
                    }
                }
                .frame(height: 6)

                Text("\(Int(percentage))%")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundColor(barColor)
                    .frame(width: 36, alignment: .trailing)
            }

            // Token breakdown row
            HStack(spacing: 12) {
                TokenLabel(label: "In", value: usage.inputTokens, color: .blue)
                TokenLabel(label: "Out", value: usage.outputTokens, color: .purple)
                TokenLabel(label: "Cache", value: usage.cacheReadInputTokens, color: .cyan)

                Spacer()

                Text("\(formatTokens(usage.totalTokens)) / 200k")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1000 {
            return "\(tokens / 1000)k"
        }
        return "\(tokens)"
    }
}

struct TokenLabel: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: 4, height: 4)
            Text("\(label):")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(formatValue(value))
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    private func formatValue(_ v: Int) -> String {
        if v >= 1000 {
            return "\(v / 1000)k"
        }
        return "\(v)"
    }
}

#Preview {
    ClaudeCodeStatsView()
        .background(Color.black.opacity(0.9))
        .cornerRadius(12)
        .padding()
}
