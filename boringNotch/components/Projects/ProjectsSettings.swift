//
//  ProjectsSettings.swift
//  boringNotch
//
//  Full management of project run commands: rename, edit the command, change
//  the folder, reorder/delete, and add new ones.
//

import AppKit
import Defaults
import SwiftUI

struct ProjectsSettings: View {
    @Default(.projectRunConfigs) var configs

    var body: some View {
        Form {
            Section {
                if configs.isEmpty {
                    Text("No projects yet. Add one below or from the Projects tab in the notch.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                }
                ForEach($configs) { $config in
                    projectEditor($config)
                }
                .onDelete { configs.remove(atOffsets: $0) }
                .onMove { configs.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Projects")
            } footer: {
                Text("Each command runs in a login shell from the project folder. Stopping a project terminates the command and any processes it spawned (e.g. dev servers).")
            }

            Section {
                Button {
                    addProject()
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Projects")
    }

    private func projectEditor(_ config: Binding<ProjectRunConfig>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: config.name)
                .font(.headline)
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField("Command", text: config.command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack(spacing: 8) {
                Text(config.directory.wrappedValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…") {
                    chooseDirectory(for: config)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private func addProject() {
        guard let url = pickDirectory(message: "Choose a project folder (one with a Makefile)") else {
            // Still allow adding a placeholder the user can fill in.
            configs.append(ProjectRunConfig(name: "New Project", directory: "", command: "make"))
            return
        }
        configs.append(ProjectRunConfig(name: url.lastPathComponent, directory: url.path, command: "make"))
    }

    private func chooseDirectory(for config: Binding<ProjectRunConfig>) {
        guard let url = pickDirectory(message: "Choose the project folder") else { return }
        config.directory.wrappedValue = url.path
        if config.name.wrappedValue.isEmpty || config.name.wrappedValue == "New Project" {
            config.name.wrappedValue = url.lastPathComponent
        }
    }

    private func pickDirectory(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = "Select"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
