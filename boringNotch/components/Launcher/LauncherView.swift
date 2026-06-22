//
//  LauncherView.swift
//  boringNotch
//
//  One-click launcher grid: pinned apps, folders, scripts and files. Tap a tile
//  to launch it; right-click to remove. The Add tile pins a new target via a
//  file picker.
//

import AppKit
import Defaults
import SwiftUI

struct LauncherView: View {
    @Default(.launcherItems) private var items

    private let columns = [GridItem(.adaptive(minimum: 66, maximum: 84), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if items.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(items) { item in
                            tile(item)
                        }
                        addTile
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: addItem) {
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

            Spacer()

            Text("LAUNCH")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.6)
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Tiles

    private func tile(_ item: LauncherItem) -> some View {
        Button(action: { LauncherManager.launch(item) }) {
            VStack(spacing: 4) {
                Image(nsImage: LauncherManager.icon(for: item))
                    .resizable()
                    .frame(width: 30, height: 30)
                Text(item.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(LauncherTilePress())
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            }
            Button("Remove", role: .destructive) { remove(item) }
        }
        .help(item.path)
    }

    private var addTile: some View {
        Button(action: addItem) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 30, height: 30)
                Text("Add")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundColor(.white.opacity(0.15))
            )
        }
        .buttonStyle(LauncherTilePress())
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.25))
            Text("No shortcuts yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text("Tap Add to pin an app, folder, or script")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func remove(_ item: LauncherItem) {
        items.removeAll { $0.id == item.id }
    }

    private func addItem() {
        // Same activation-policy dance as Projects: become a regular app so the
        // open panel comes forward above the notch overlay, then restore.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Pin"
        panel.message = "Choose apps, folders, scripts, or files to pin"
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.level = .mainMenu + 4
        let response = panel.runModal()

        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()

        guard response == .OK else { return }
        for url in panel.urls {
            let item = LauncherManager.makeItem(for: url)
            if !items.contains(where: { $0.path == item.path }) {
                items.append(item)
            }
        }
    }
}

/// Press feedback for launcher tiles.
private struct LauncherTilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    LauncherView()
        .frame(width: 580, height: 160)
        .background(.black)
}
