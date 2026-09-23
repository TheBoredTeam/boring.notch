//
//  NotchTerminalView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftTerm
import SwiftUI

private struct TerminalProcessView: NSViewRepresentable {
    @ObservedObject var manager: TerminalSessionManager

    func makeCoordinator() -> Coordinator { Coordinator(manager: manager) }

    func makeNSView(context: Context) -> NSView {
        manager.mount(delegate: context.coordinator)
        return manager.hostView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        manager.mount(delegate: context.coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
        let manager: TerminalSessionManager

        init(manager: TerminalSessionManager) {
            self.manager = manager
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            manager.setTitle(title)
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            manager.shellDidExit(source: source)
        }
    }
}

struct NotchTerminalView: View {
    @ObservedObject var manager: TerminalSessionManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "apple.terminal")
                Text(manager.title)
                    .lineLimit(1)
                Spacer()
                if !manager.isRunning {
                    Text("Exited")
                        .foregroundStyle(.secondary)
                }
                Button {
                    manager.restart()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .help("Restart shell")
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 30)

            TerminalProcessView(manager: manager)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            if let errorMessage = manager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                manager.focus()
            }
        }
        .onDisappear {
            manager.resignFocus()
        }
    }
}
