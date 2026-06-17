//
//  ProjectsView.swift
//  boringNotch
//
//  Quick launcher: tap a project to run its command (e.g. `make`), tap again
//  to stop it. Add new projects inline via a folder picker; fine-tune the
//  command in Settings → Projects.
//

import AppKit
import Defaults
import SwiftUI

struct ProjectsView: View {
    @Default(.projectRunConfigs) private var configs
    @ObservedObject private var manager = ProjectsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if configs.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(configs) { config in
                            projectRow(config)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("PROJECTS")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.6)
                .foregroundColor(.white.opacity(0.4))
            if manager.runningIDs.count > 0 {
                Text("\(manager.runningIDs.count) running")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(red: 0.4, green: 0.85, blue: 0.6))
            }
            Spacer()
            Button(action: addProject) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("Add")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Row

    private func projectRow(_ config: ProjectRunConfig) -> some View {
        let running = manager.isRunning(config.id)
        return HStack(spacing: 10) {
            Circle()
                .fill(running ? Color(red: 0.4, green: 0.85, blue: 0.6) : Color.white.opacity(0.18))
                .frame(width: 7, height: 7)
                .shadow(color: running ? Color(red: 0.4, green: 0.85, blue: 0.6).opacity(0.6) : .clear, radius: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(config.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(config.command)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button(action: { manager.toggle(config) }) {
                HStack(spacing: 5) {
                    Image(systemName: running ? "stop.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(running ? "Stop" : "Run")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(running ? .white : .black)
                .frame(width: 64, height: 26)
                .background(
                    Capsule().fill(running ? Color(red: 1, green: 0.42, blue: 0.42) : Color(red: 0.4, green: 0.85, blue: 0.6))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.25))
            Text("No projects yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text("Tap Add to pick a project folder")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"
        panel.message = "Choose a project folder (one with a Makefile)"
        panel.level = .modalPanel
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let new = ProjectRunConfig(
            name: url.lastPathComponent,
            directory: url.path,
            command: "make"
        )
        configs.append(new)
    }
}

#Preview {
    ProjectsView()
        .frame(width: 580, height: 160)
        .background(.black)
}
