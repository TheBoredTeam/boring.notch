//
//  SessionPicker.swift
//  boringNotch
//
//  Dropdown menu for selecting which Claude Code session to monitor
//

import SwiftUI

struct SessionPicker: View {
    @ObservedObject var manager: ClaudeCodeManager

    var body: some View {
        Menu {
            if manager.availableSessions.isEmpty {
                Text("No active sessions")
                    .foregroundColor(.secondary)
            } else {
                ForEach(manager.availableSessions) { session in
                    Button(action: { manager.selectSession(session) }) {
                        HStack {
                            Image(systemName: ideIcon(for: session.ideName))
                            VStack(alignment: .leading) {
                                Text(session.displayName)
                                Text(session.ideName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if session.pid == manager.selectedSession?.pid {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button(action: { manager.scanForSessions() }) {
                Label("Refresh Sessions", systemImage: "arrow.clockwise")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12))

                if let session = manager.selectedSession {
                    Text(session.displayName)
                        .lineLimit(1)
                } else {
                    Text("Select Session")
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
    }

    private func ideIcon(for ideName: String) -> String {
        switch ideName.lowercased() {
        case "cursor":
            return "cursorarrow.rays"
        case "vscode", "visual studio code":
            return "chevron.left.forwardslash.chevron.right"
        case "xcode":
            return "hammer.fill"
        case "terminal":
            return "terminal"
        default:
            return "laptopcomputer"
        }
    }
}

struct SessionPickerCompact: View {
    @ObservedObject var manager: ClaudeCodeManager

    var body: some View {
        Menu {
            ForEach(manager.availableSessions) { session in
                Button(session.displayName) {
                    manager.selectSession(session)
                }
            }

            if manager.availableSessions.isEmpty {
                Text("No sessions")
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(manager.selectedSession != nil ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)

                if let session = manager.selectedSession {
                    Text(session.displayName)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
        .menuStyle(.borderlessButton)
    }
}

#Preview {
    VStack(spacing: 20) {
        SessionPicker(manager: ClaudeCodeManager.shared)
        SessionPickerCompact(manager: ClaudeCodeManager.shared)
    }
    .padding()
    .frame(width: 300)
    .background(Color.black.opacity(0.8))
}
