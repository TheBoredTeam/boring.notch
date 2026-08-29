//
//  AIAgentPanel.swift
//  boringNotch
//
//  The Agent tab inside the open notch: sessions list ↔ chat view.
//  Compact, fast, keyboard-navigable. 640×190 notch constraint.
//

import SwiftUI
import Defaults

struct AIAgentPanel: View {
    @ObservedObject private var vm = AIAgentViewModel.shared
    @State private var draft = ""
    @State private var showNewSessionAlert = false
    @Namespace private var animation

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider().overlay(Color.white.opacity(0.08))

            if vm.sessions.isEmpty {
                emptyState
            } else if vm.selectedSessionID == nil {
                sessionsList
            } else {
                chatView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AgentPalette.ink)
        .onAppear { vm.activate() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            // Status dot + label
            HStack(spacing: 6) {
                AgentStateDot(
                    color: vm.connected ? (vm.connected ? .green : .yellow) : .gray,
                    pulsing: vm.connected && vm.sessions.contains { $0.phase == .busy },
                    size: 8
                )
                Text(vm.connected ? "Claude Code" : (vm.claudeMissing ? "Claude Code missing" : "Claude Code"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(vm.connected ? AgentPalette.paper : AgentPalette.paperFaint)
            }

            Spacer()

            // Session picker menu (when in list mode)
            if vm.selectedSessionID == nil && !vm.sessions.isEmpty {
                Menu {
                    ForEach(vm.sessions) { session in
                        Button {
                            vm.openChat(sessionID: session.id)
                        } label: {
                            HStack {
                                AgentStateDot(color: AgentPalette.tint(for: session.phase), size: 6)
                                Text(session.displayTitle)
                                    .font(.system(size: 11, weight: .medium))
                                if let model = session.modelRef {
                                    Text(model)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(AgentPalette.paperFaint)
                                }
                            }
                        }
                    }
                    Divider()
                    Button { Task { await vm.startNewSession() } } label: {
                        Label("New Session", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Sessions")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(AgentPalette.paper)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            // New session
            if vm.selectedSessionID == nil {
                Button { Task { await vm.startNewSession() } } label: {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AgentPalette.paper)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("New session")
            }

            // Model picker — always visible while a session is open so the
            // user can change the model; label falls back to "Select model".
            if vm.selectedSessionID != nil {
                Menu {
                    if vm.availableModels.isEmpty {
                        Text("Loading models…")
                            .font(.system(size: 11))
                            .foregroundStyle(AgentPalette.paperFaint)
                    }
                    ForEach(vm.availableModels) { m in
                        Button { Task { await vm.switchModel(m) } } label: {
                            HStack {
                                Text(m.name ?? m.id).font(.system(size: 11))
                                if let ref = vm.selectedSession?.modelRef, m.ref == ref {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(vm.selectedModel?.name ?? vm.selectedSession?.modelRef ?? "Select model")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(AgentPalette.paper)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            // Back button (from chat to list)
            if vm.selectedSessionID != nil {
                Button { vm.closeChat() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AgentPalette.paper)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("Back to sessions")
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 28))
                .foregroundStyle(AgentPalette.paperFaint)

            if vm.claudeMissing {
                Text("Claude Code CLI not found")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AgentPalette.paperSecondary)
                Text("Install it with:\nnpm install -g @anthropic-ai/claude-code")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AgentPalette.paperFaint)
                    .multilineTextAlignment(.center)
            } else if vm.needsAuth {
                Text("Claude Code needs authentication")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AgentPalette.paperSecondary)
                Button {
                    ClaudeCodeAuthOpener.openTerminalLogin()
                } label: {
                    Label("Authenticate", systemImage: "person.badge.key.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AgentPalette.completed)
            } else if vm.sessions.isEmpty {
                Text("No sessions yet")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AgentPalette.paperSecondary)
                Button { Task { await vm.startNewSession() } } label: {
                    Label("Create Session", systemImage: "plus.bubble")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AgentPalette.completed)
            } else {
                Text(vm.connected ? "All caught up" : "Start Claude Code in any project to connect")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AgentPalette.paperSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Sessions list

    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.sessions) { session in
                    SessionRow(session: session, isSelected: false) {
                        vm.openChat(sessionID: session.id)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(
                        Rectangle()
                            .fill(Color.white.opacity(0.02))
                            .overlay(Rectangle().fill(Color.white.opacity(0.04)).frame(height: 0.5), alignment: .bottom)
                    )
                    .onTapGesture { vm.openChat(sessionID: session.id) }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Chat view

    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                        if vm.chatLoading || vm.sending || vm.selectedSession?.phase == .busy {
                            HStack(spacing: 6) {
                                Spacer()
                                AgentStateDot(
                                    color: vm.selectedSession?.phase == .busy
                                        ? AgentPalette.running : AgentPalette.waiting,
                                    pulsing: true, size: 7)
                                Text(vm.selectedSession?.phase == .busy
                                     ? "Claude is thinking…"
                                     : (vm.sending ? "Sending…" : "Loading…"))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(AgentPalette.paperFaint)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: vm.sending) { _, new in
                    if new, let last = vm.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.08))

            // Input bar
            HStack(spacing: 8) {
                TextField(vm.sending || vm.isSessionRunning ? "Working…" : "Message…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AgentPalette.paper)
                    .lineLimit(1...4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                    )
                    .disabled(vm.sending || vm.isSessionRunning)
                    .onSubmit { send() }

                if vm.sending || vm.isSessionRunning {
                    Button { vm.interrupt() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AgentPalette.waitingApproval)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help("Interrupt")
                } else {
                    Button { send() } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AgentPalette.paper)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func send() {
        guard !vm.sending else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await vm.sendPrompt(text) }
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: AgentSession
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AgentStateDot(
                color: AgentPalette.tint(for: session.phase),
                pulsing: session.phase == .busy || session.phase == .waitingApproval || session.phase == .waitingAnswer,
                size: 8
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AgentPalette.paper)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    if let tool = session.lastTool {
                        AgentChip(text: tool, tint: AgentPalette.paperFaint)
                    }
                    if let model = session.modelRef {
                        AgentChip(text: model.hasPrefix("claude/") ? String(model.dropFirst("claude/".count)) : model,
                                  tint: AgentPalette.paperFaint)
                    }
                    if session.phase == .waitingApproval {
                        AgentChip(text: "needs you", tint: AgentPalette.waitingApproval)
                    } else if session.phase == .waitingAnswer {
                        AgentChip(text: "question", tint: AgentPalette.waitingAnswer)
                    }
                    Text(AgentAge.string(from: session.updatedAt))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AgentPalette.paperFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AgentPalette.paperFaint)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: AgentChatMessage

    var body: some View {
        if message.role == .system {
            HStack {
                Spacer()
                Text(message.text)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(AgentPalette.paperFaint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
                Spacer()
            }
        } else {
            HStack {
                if message.role == .user { Spacer(minLength: 40) }

                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                    if message.role != .error {
                        Text(message.role == .user ? "You" : "Agent")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(AgentPalette.paperFaint)
                    }
                    Text(message.text)
                        .font(.system(size: 11))
                        .foregroundStyle(message.role == .user ? AgentPalette.paper : AgentPalette.paper.opacity(0.95))
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(message.role == .user
                                    ? Color.white.opacity(0.12)
                                    : Color.white.opacity(0.05))
                        )
                }

                if message.role == .assistant || message.role == .error { Spacer(minLength: 40) }
            }
        }
    }
}