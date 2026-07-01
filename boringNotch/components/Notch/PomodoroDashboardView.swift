//
//  PomodoroDashboardView.swift
//  boringNotch
//
//  Created by Codex on 2026-06-30.
//

import Defaults
import SwiftUI

struct PomodoroDashboardView: View {
    @Default(.pomodoroEnabled) private var pomodoroEnabled

    @ObservedObject private var manager = PomodoroManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !pomodoroEnabled {
                featureDisabledState(
                    title: "Pomodoro is disabled",
                    subtitle: "Enable it in Settings > Pomodoro to use the focus timer."
                )
            } else {
                timerCard
                phaseSelector
                statsRow
                controls
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pomodoro")
                    .font(.headline)
                Text(manager.phase.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: manager.phase.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor(for: manager.phase))
        }
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(manager.formattedRemaining)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Spacer()

                Text(manager.isRunning ? "Running" : "Ready")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: manager.progress)
                .progressViewStyle(.linear)
                .tint(accentColor(for: manager.phase))

            Text("Next: \(manager.nextPhaseTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var phaseSelector: some View {
        HStack(spacing: 8) {
            ForEach(PomodoroPhase.allCases) { phase in
                Button {
                    manager.selectPhase(phase)
                } label: {
                    Text(phase.shortLabel)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(manager.phase == phase ? accentColor(for: phase).opacity(0.24) : Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(manager.phase == phase ? Color.effectiveAccent : .primary)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            PomodoroStatTile(title: "Session", value: manager.currentCycleIndexLabel)
            PomodoroStatTile(title: "Completed", value: "\(manager.completedFocusSessions)")
            PomodoroStatTile(title: "Auto-start", value: Defaults[.pomodoroAutoStartNextPhase] ? "On" : "Off")
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                manager.toggleRunning()
            } label: {
                Label(manager.isRunning ? "Pause" : "Start", systemImage: manager.isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor(for: manager.phase))

            Button {
                manager.resetCurrentPhase()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 28)
            }
            .buttonStyle(.bordered)
            .help("Reset current phase")

            Button {
                manager.skipPhase()
            } label: {
                Image(systemName: "forward.fill")
                    .frame(width: 28)
            }
            .buttonStyle(.bordered)
            .help("Skip to next phase")

            Button {
                manager.resetCycle()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 28)
            }
            .buttonStyle(.bordered)
            .help("Reset full cycle")
        }
        .controlSize(.small)
    }

    private func featureDisabledState(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Open Settings") {
                SettingsWindowController.shared.showWindow()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func accentColor(for phase: PomodoroPhase) -> Color {
        switch phase {
        case .focus:
            return Color.effectiveAccent
        case .shortBreak:
            return .green
        case .longBreak:
            return .orange
        }
    }
}

private struct PomodoroStatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
