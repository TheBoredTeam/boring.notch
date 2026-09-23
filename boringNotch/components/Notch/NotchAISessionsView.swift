//
//  NotchAISessionsView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import SwiftUI

struct NotchAISessionsView: View {
    @ObservedObject private var approvalBridge = ClaudeApprovalBridge.shared
    @State private var sessions: [AISessionRecord] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                Text("AI Sessions")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(sessions.filter { $0.status == .working }.count) working")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh sessions")
            }
            .padding(.horizontal, 14)

            if let approval = approvalBridge.pending.first {
                approvalCard(approval)
                    .padding(.horizontal, 12)
            }

            if sessions.isEmpty && approvalBridge.pending.isEmpty {
                ContentUnavailableView(
                    isLoading ? "Loading sessions" : "No recent sessions",
                    systemImage: "sparkles",
                    description: Text("Recent Codex and Claude Code sessions appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(sessions) { session in
                            sessionCard(session)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func approvalCard(_ request: ClaudeApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permission requested · \(request.projectName)")
                .font(.system(size: 11, weight: .semibold))
            Text(request.toolName)
                .font(.system(size: 10, weight: .medium))
            ScrollView {
                Text(request.detail)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 90)
            HStack {
                Button("Allow once") {
                    approvalBridge.respond(to: request.id, allow: true)
                }
                Button("Deny") {
                    approvalBridge.respond(to: request.id, allow: false)
                }
            }
            .font(.system(size: 10, weight: .medium))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sessionCard(_ session: AISessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(session.status == .working ? .green : .gray)
                    .frame(width: 6, height: 6)
                Text(session.source.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(session.projectName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(session.status.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(session.lastActivity, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if let message = session.latestMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if session.isDesktopSession,
               let threadID = session.id.split(separator: ":", maxSplits: 1).last,
               let url = URL(string: "codex://threads/\(threadID)") {
                Button("Open in Codex") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func refresh() async {
        let latest = await Task.detached(priority: .utility) {
            AISessionScanner.scan()
        }.value
        guard !Task.isCancelled else { return }
        sessions = latest
        isLoading = false
    }
}
