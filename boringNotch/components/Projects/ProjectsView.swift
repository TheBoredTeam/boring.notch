//
//  ProjectsView.swift
//  boringNotch
//
//  Quick launcher: tap a project to run its command (e.g. `make`), tap again
//  to stop it. Restart, view live logs, and tap a detected port to open it in
//  the browser. Add new projects inline via a folder picker; fine-tune the
//  command in Settings → Projects.
//

import AppKit
import Defaults
import SwiftUI

struct ProjectsView: View {
    @Default(.projectRunConfigs) private var configs
    @Default(.projectsAutoOpenPort) private var autoOpenPort
    @ObservedObject private var manager = ProjectsManager.shared
    @State private var logProjectID: UUID?

    private let green = Color(red: 0.4, green: 0.85, blue: 0.6)
    private let red = Color(red: 1, green: 0.42, blue: 0.42)

    var body: some View {
        ZStack {
            mainView
            if let id = logProjectID, let config = configs.first(where: { $0.id == id }) {
                logOverlay(config)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.snappy(duration: 0.25), value: logProjectID)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var mainView: some View {
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: addProject) {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                    Text("Add").font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)

            // Auto-open detected port in the browser.
            Button(action: { autoOpenPort.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: autoOpenPort ? "globe" : "globe.badge.chevron.backward")
                        .font(.system(size: 9, weight: .bold))
                    Text("Auto-open").font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(autoOpenPort ? .black : .white.opacity(0.6))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(autoOpenPort ? green : Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .help("Open a project's port in the browser as soon as it starts listening")

            if !manager.runningIDs.isEmpty {
                Button(action: { manager.stopAll() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill").font(.system(size: 8, weight: .bold))
                        Text("Stop All").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(red))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if !manager.runningIDs.isEmpty {
                Text("\(manager.runningIDs.count) running")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(green)
            }
            Text("PROJECTS")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.6)
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Row

    private func projectRow(_ config: ProjectRunConfig) -> some View {
        let running = manager.isRunning(config.id)
        return HStack(spacing: 8) {
            Circle()
                .fill(running ? green : Color.white.opacity(0.18))
                .frame(width: 7, height: 7)
                .shadow(color: running ? green.opacity(0.6) : .clear, radius: 3)

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

            // Tappable port pills → open in browser.
            if running, let ports = manager.portsByProject[config.id], !ports.isEmpty {
                HStack(spacing: 4) {
                    ForEach(ports.prefix(2), id: \.self) { port in
                        Button(action: { manager.openPort(port) }) {
                            HStack(spacing: 2) {
                                Text(":\(port)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                Image(systemName: "arrow.up.right").font(.system(size: 6, weight: .bold))
                            }
                            .foregroundColor(green)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(Capsule().fill(green.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .help("Open http://localhost:\(port)")
                    }
                }
            }

            // Logs
            iconButton("terminal", active: logProjectID == config.id) {
                logProjectID = config.id
            }

            // Restart (running only)
            if running {
                iconButton("arrow.clockwise") { manager.restart(config) }
            }

            // Run / Stop
            Button(action: { manager.toggle(config) }) {
                HStack(spacing: 5) {
                    Image(systemName: running ? "stop.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(running ? "Stop" : "Run")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(running ? .white : .black)
                .frame(width: 60, height: 26)
                .background(Capsule().fill(running ? red : green))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    private func iconButton(_ icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(active ? .black : .white.opacity(0.7))
                .frame(width: 26, height: 26)
                .background(Circle().fill(active ? .white.opacity(0.85) : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log overlay

    private func logOverlay(_ config: ProjectRunConfig) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button(action: { logProjectID = nil }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                Text(config.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Circle()
                    .fill(manager.isRunning(config.id) ? green : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)
                Spacer()
                Text("LOGS")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.3))
                Button(action: { manager.clearLogs(config.id) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Clear log buffer")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    let logs = manager.logsByProject[config.id] ?? ""
                    Text(logs.isEmpty ? "Waiting for output…" : logs)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(logs.isEmpty ? .white.opacity(0.3) : .white.opacity(0.8))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("logbottom")
                }
                .onChange(of: manager.logsByProject[config.id]) { _, _ in
                    withAnimation { proxy.scrollTo("logbottom", anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo("logbottom", anchor: .bottom) }
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.4)))
        }
        .padding(.bottom, 2)
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
        // The notch is an accessory-app overlay at .mainMenu + 3. To get an
        // NSOpenPanel in front and focusable we must temporarily become a
        // regular app and raise the panel above the notch window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"
        panel.message = "Choose a project folder (one with a Makefile)"
        panel.level = .mainMenu + 4
        let response = panel.runModal()

        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()

        guard response == .OK, let url = panel.url else { return }
        configs.append(ProjectRunConfig(
            name: url.lastPathComponent,
            directory: url.path,
            command: "make"
        ))
    }
}

#Preview {
    ProjectsView()
        .frame(width: 580, height: 160)
        .background(.black)
}
