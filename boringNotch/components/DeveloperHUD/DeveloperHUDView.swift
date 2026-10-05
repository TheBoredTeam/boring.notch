//
//  DeveloperHUDView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct DeveloperHUDView: View {
    @ObservedObject private var manager = DeveloperHUDManager.shared
    @Default(.devHUDShowGit) private var showGit
    @Default(.devHUDShowLastCommit) private var showLastCommit
    @Default(.devHUDShowSystem) private var showSystem
    @Default(.devHUDShowBuild) private var showBuild
    @Default(.devHUDShowServers) private var showServers
    @Default(.devHUDShowTasks) private var showTasks

    @State private var expanded = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                if showGit { gitSection }
                statusRow
                if expanded { expandedSection.transition(.blurReplace) }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { manager.start() }
        .onDisappear { manager.stop() }
    }

    // MARK: Git

    @ViewBuilder
    private var gitSection: some View {
        switch manager.gitState {
        case .idle, .loading:
            HUDStateView(kind: .loading, title: "Reading repository…")
                .frame(height: 50)
        case .noProject:
            HUDStateView(kind: .empty, title: "No project selected",
                         message: "Choose a project folder in Settings › Developer HUD.",
                         buttonTitle: "Open Settings") { SettingsWindowController.shared.showWindow() }
                .frame(height: 50)
        case .notARepository:
            HUDStateView(kind: .empty, title: "Not a Git repository",
                         message: "The selected folder has no .git directory.")
                .frame(height: 50)
        case .accessDenied:
            HUDStateView(kind: .error, title: "Can't access project",
                         message: "Re-select the folder in Settings › Developer HUD.",
                         buttonTitle: "Open Settings") { SettingsWindowController.shared.showWindow() }
                .frame(height: 50)
        case .ready(let snap):
            HUDCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill").foregroundStyle(.gray).font(.system(size: 11))
                        Text(snap.projectName)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .lineLimit(1)
                        HUDChip(text: snap.branch, systemImage: "arrow.triangle.branch", tint: .cyan)
                        statusChip(snap)
                        Spacer(minLength: 0)
                        projectPicker
                    }
                    if showLastCommit, let message = snap.lastCommitMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "text.bubble").font(.system(size: 10)).foregroundStyle(.gray)
                            Text(message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                            if let date = snap.lastCommitDate {
                                Text(date.hudRelative).font(.system(size: 10)).foregroundStyle(.gray)
                            }
                        }
                    }
                    if !snap.gitAvailable {
                        Text("Git unavailable — showing branch only.")
                            .font(.system(size: 10)).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func statusChip(_ snap: GitSnapshot) -> HUDChip {
        switch snap.status {
        case .clean: return HUDChip(text: "Clean", systemImage: "checkmark.circle.fill", tint: .green)
        case .modified: return HUDChip(text: "\(snap.changedFiles) changed", systemImage: "pencil.circle.fill", tint: .orange)
        case .untracked: return HUDChip(text: "\(snap.untrackedFiles) untracked", systemImage: "questionmark.circle.fill", tint: .yellow)
        case .unknown: return HUDChip(text: "Unknown", systemImage: "circle.dashed", tint: .gray)
        }
    }

    @ViewBuilder
    private var projectPicker: some View {
        let names = manager.projectNames
        if names.count > 1 {
            Menu {
                ForEach(Array(names.enumerated()), id: \.offset) { idx, name in
                    Button(name) { manager.selectProject(idx) }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    // MARK: Compact status row

    private var statusRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if showSystem {
                HUDCard {
                    VStack(spacing: 5) {
                        HUDGauge(label: "CPU", value: manager.metrics.cpu, tint: .green)
                        HUDGauge(label: "MEM", value: manager.metrics.memory, tint: .blue)
                    }
                }
                .frame(width: 130)
            }
            if showBuild {
                HUDCard {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Build").font(.system(size: 9, weight: .medium)).foregroundStyle(.gray)
                        if let tool = manager.environment.buildTool {
                            HUDChip(text: tool, systemImage: "hammer.fill", tint: .orange)
                        } else {
                            HUDChip(text: "Idle", systemImage: "checkmark", tint: .gray)
                        }
                    }
                }
                .frame(width: 100)
            }
            if showServers {
                HUDCard {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dev server").font(.system(size: 9, weight: .medium)).foregroundStyle(.gray)
                        if let server = manager.environment.servers.first {
                            HUDChip(text: ":\(server.port)", systemImage: "bolt.horizontal.fill", tint: .green)
                        } else {
                            HUDChip(text: "None", systemImage: "moon.zzz", tint: .gray)
                        }
                    }
                }
                .frame(width: 100)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.smooth(duration: 0.3)) { expanded.toggle() }
            } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.gray)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(expanded ? "Show less" : "Show more")
        }
    }

    // MARK: Expanded

    private var expandedSection: some View {
        HStack(alignment: .top, spacing: 8) {
            HUDCard {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Environment").font(.system(size: 9, weight: .medium)).foregroundStyle(.gray)
                    Text(manager.environment.ides.isEmpty ? "No editor running" : manager.environment.ides.joined(separator: ", "))
                        .font(.system(size: 11)).foregroundStyle(.white).lineLimit(2)
                }
            }
            if showServers && manager.environment.servers.count > 1 {
                HUDCard {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Servers").font(.system(size: 9, weight: .medium)).foregroundStyle(.gray)
                        Text(manager.environment.servers.map { "\($0.label) :\($0.port)" }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(.white).lineLimit(2)
                    }
                }
            }
            if showTasks {
                HUDCard {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Running tasks").font(.system(size: 9, weight: .medium)).foregroundStyle(.gray)
                        Text(manager.environment.tasks.isEmpty ? "None" : manager.environment.tasks.joined(separator: ", "))
                            .font(.system(size: 11)).foregroundStyle(.white).lineLimit(2)
                    }
                }
            }
        }
    }
}
