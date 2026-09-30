//
//  AgentsTabView.swift
//  boringCode
//
//  Aba "Agentes" do notch aberto: sessões do Claude Code, aprovar/recusar e
//  clique para voltar ao terminal/editor.
//

import Defaults
import SwiftUI

struct AgentsTabView: View {
    @ObservedObject private var store = AgentSessionStore.shared

    /// Pendentes primeiro, depois ativas, depois o resto — dentro de cada grupo, mais recentes primeiro.
    private var orderedSessions: [AgentSession] {
        store.sessions.enumerated().sorted { lhs, rhs in
            let left = rank(lhs.element)
            let right = rank(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left > right
        }.map(\.element)
    }

    private func rank(_ session: AgentSession) -> Int {
        if session.needsAnswer { return 100 }
        return session.status.isActive ? session.status.priority + 10 : 0
    }

    var body: some View {
        Group {
            if store.sessions.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 6) {
                        ForEach(orderedSessions) { session in
                            VStack(spacing: 4) {
                                AgentSessionRow(session: session)
                                if let question = session.pendingQuestion {
                                    AgentQuestionCard(sessionID: session.id, pending: question)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.top, 2)
                    .animation(.smooth(duration: 0.3), value: store.sessions)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "apple.terminal")
                .symbolVariant(.fill)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white, .gray)
                .imageScale(.large)

            Text("No active Claude Code sessions")
                .foregroundStyle(.gray)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.medium)

            switch store.hookState {
            case .installed:
                Text("Start `claude` in a terminal or use Claude in VS Code.")
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.8))
            case .claudeNotFound:
                Text("Claude Code isn't installed on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.8))
            default:
                Button {
                    store.installHooksIfNeeded()
                } label: {
                    Text("Connect to Claude Code")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AgentSessionRow: View {
    let session: AgentSession
    @ObservedObject private var store = AgentSessionStore.shared
    @State private var isHovering = false

    private var subtitle: String {
        if let permission = session.pendingPermission {
            return permission.summary.isEmpty ? permission.toolName : "\(permission.toolName) · \(permission.summary)"
        }
        if session.status == .error, let error = session.errorMessage { return error }
        if session.status.isActive, let activity = session.activity { return activity }
        return session.lastPrompt ?? session.status.label
    }

    var body: some View {
        HStack(spacing: 10) {
            AgentStatusIndicator(status: session.status, size: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(session.host.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .fixedSize()
                    if session.subagents > 0 {
                        Label("\(session.subagents)", systemImage: "person.2.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.gray)
                            .labelStyle(.titleAndIcon)
                            .fixedSize()
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11, design: session.pendingPermission != nil ? .monospaced : .default))
                    .foregroundStyle(.gray)
                    .lineLimit(session.pendingPermission != nil ? 2 : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if session.pendingPermission != nil {
                HStack(spacing: 6) {
                    rowButton("Deny", prominent: false) { store.deny(session.id) }
                    rowButton("Allow", prominent: true) { store.approve(session.id) }
                }
                .fixedSize()
            } else {
                Text(session.status.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(session.status.isActive ? session.status.tint : .gray)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.1 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.yellow.opacity(session.pendingPermission != nil ? 0.35 : 0), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture { store.focus(session) }
        .help(Text("Go to \(session.host.displayName)"))
        .contextMenu {
            Button("Go to \(session.host.displayName)") { store.focus(session) }
            if !session.status.isActive {
                Button("Remove from list") { store.dismiss(session.id) }
            }
        }
    }

    private func rowButton(_ title: LocalizedStringKey, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(prominent ? .black : .white)
                .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
