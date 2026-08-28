//
//  AIAgentFullView.swift
//  boringNotch
//
//  Full desktop window for driving Claude Code: session sidebar,
//  transcript, prompt input, and inline approve/deny of permission
//  and question prompts — the Vibe Island-style cockpit.
//

import SwiftUI
import Defaults

struct AIAgentFullView: View {
    @ObservedObject private var vm = AIAgentViewModel.shared
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 0) {
            sessionSidebar
                .frame(minWidth: 220, maxWidth: 260)
                .background(AgentPalette.ink)

            Divider().overlay(Color.white.opacity(0.08))

            VStack(spacing: 0) {
                transcript
                Divider().overlay(Color.white.opacity(0.08))
                promptBar
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    // MARK: Sidebar

    private var sessionSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sessions")
                    .font(.headline)
                    .foregroundStyle(AgentPalette.paper)
                Spacer()
                Button { Task { await vm.startNewSession() } } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            Divider().overlay(Color.white.opacity(0.08))

            List(vm.sessions, selection: Binding(
                get: { vm.selectedSessionID },
                set: { if let id = $0 { vm.openChat(sessionID: id) } }
            )) { session in
                SessionFullRow(session: session)
                    .padding(.vertical, 2)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(vm.messages) { message in
                        ChatBubbleFull(message: message)
                            .id(message.id)
                    }

                    if !vm.pendingPermissions.isEmpty {
                        ForEach(vm.pendingPermissions) { request in
                            PermissionCardFull(request: request)
                        }
                    }

                    if !vm.pendingQuestions.isEmpty {
                        ForEach(vm.pendingQuestions) { request in
                            QuestionCardFull(request: request)
                        }
                    }

                    if vm.sending {
                        HStack {
                            AgentStateDot(color: AgentPalette.running, pulsing: true, size: 7)
                            Text("Agent is working…")
                                .font(.caption)
                                .foregroundStyle(AgentPalette.paperSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
            }
            .onChange(of: vm.messages.count + vm.pendingPermissions.count + vm.pendingQuestions.count) {
                if let last = vm.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: Prompt bar

    private var promptBar: some View {
        HStack(spacing: 10) {
            TextField("Send a prompt to your agent…", text: $draft, onCommit: send)
                .textFieldStyle(.roundedBorder)
                .disabled(vm.sending)
            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || vm.sending)
            Button(action: { vm.interrupt() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .help("Interrupt")
        }
        .padding(12)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await vm.sendPrompt(text) }
    }
}

// MARK: - Session full row

private struct SessionFullRow: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                AgentStateDot(color: AgentPalette.tint(for: session.phase), size: 8)
                Text(session.displayTitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AgentPalette.paper)
                    .lineLimit(1)
            }

            if let model = session.modelRef {
                Text(model)
                    .font(.caption2)
                    .foregroundStyle(AgentPalette.paperSecondary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Full transcript bubble

private struct ChatBubbleFull: View {
    let message: AgentChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 3) {
                Text(message.role == .user ? "You" : "Agent")
                    .font(.caption2)
                    .foregroundStyle(AgentPalette.paperSecondary)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(message.role == .user
                                ? Color.accentColor.opacity(0.22)
                                : Color(nsColor: .secondarySystemFill))
                    )
            }
            if message.role == .assistant { Spacer() }
        }
    }
}

// MARK: - Full permission card

private struct PermissionCardFull: View {
    @ObservedObject private var vm = AIAgentViewModel.shared
    let request: AgentPendingPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(request.title, systemImage: "hand.raised.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
            if !request.detail.isEmpty {
                Text(request.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AgentPalette.paperSecondary)
            }
            HStack(spacing: 10) {
                Button("Approve") { vm.approve(permission: request) }
                    .buttonStyle(.borderedProminent)
                Button("Always") { vm.approve(permission: request, always: true) }
                    .buttonStyle(.bordered)
                Button("Deny") { vm.deny(permission: request) }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.12)))
    }
}

// MARK: - Full question card

private struct QuestionCardFull: View {
    @ObservedObject private var vm = AIAgentViewModel.shared
    let request: AgentPendingQuestion
    @State private var customAnswer = ""
    @State private var submitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Question", systemImage: "questionmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.blue)

            ForEach(request.questions) { q in
                VStack(alignment: .leading, spacing: 6) {
                    Text(q.question).font(.callout)
                    if !q.options.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(q.options) { opt in
                                Button {
                                    vm.answer(question: request, answers: [[opt.label]])
                                } label: {
                                    Text(opt.label)
                                        .font(.callout.weight(.medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(submitting)
                            }
                        }
                    }
                    HStack {
                        TextField("Type your answer…", text: $customAnswer, onCommit: submitCustom)
                            .textFieldStyle(.roundedBorder)
                        Button("Send") { submitCustom() }
                            .buttonStyle(.borderedProminent)
                            .disabled(customAnswer.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue.opacity(0.12)))
    }

    private func submitCustom() {
        let text = customAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        customAnswer = ""
        vm.answer(question: request, answers: [[text]])
    }
}