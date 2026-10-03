//
//  NotchAISessionsView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import SwiftUI

struct NotchAISessionsView: View {
    let previewSessions: [AISessionRecord]?
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var approvalBridge = ClaudeApprovalBridge.shared
    @ObservedObject private var monitor = AISessionMonitor.shared
    @ObservedObject private var focusService = AISessionFocusService.shared
    @State private var questionWindow: BoringNotchSkyLightWindow?

    init(previewSessions: [AISessionRecord]? = nil) {
        self.previewSessions = previewSessions
    }

    private var displayedSessions: [AISessionRecord] {
        previewSessions ?? monitor.sessions
    }

    private var displayedCompletions: [AISessionCompletion] {
        previewSessions == nil ? monitor.completions : []
    }

    private var displayedQuestions: [ClaudeQuestionRequest] {
        previewSessions == nil ? approvalBridge.pendingQuestions : []
    }

    private var displayedApprovals: [ClaudeApprovalRequest] {
        previewSessions == nil ? approvalBridge.pending : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                Text("AI Sessions")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(displayedSessions.filter { $0.status == .working }.count) working")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await monitor.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh sessions")
            }
            .padding(.horizontal, 14)

            if displayedSessions.isEmpty && displayedCompletions.isEmpty
                && displayedApprovals.isEmpty && displayedQuestions.isEmpty {
                ContentUnavailableView(
                    previewSessions == nil && monitor.isLoading
                        ? "Loading sessions" : "No recent sessions",
                    systemImage: "sparkles",
                    description: Text("Recent Codex, Claude Code, and OpenClaw sessions appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(displayedCompletions) { completion in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("\(completion.source.rawValue) finished · \(completion.projectName)")
                                    .font(.system(size: 10, weight: .medium))
                                Spacer()
                                Button {
                                    monitor.dismissCompletion(id: completion.id)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        }
                        ForEach(displayedQuestions) { request in
                            ClaudeQuestionCard(request: request) { answers in
                                approvalBridge.answerQuestion(id: request.id, answers: answers)
                            } onFallback: {
                                approvalBridge.answerInClaude(id: request.id)
                            }
                        }
                        ForEach(displayedApprovals) { approval in
                            approvalCard(approval)
                        }
                        ForEach(displayedSessions) { session in
                            sessionCard(session)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.top, 8)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard previewSessions == nil else { return }
            updateQuestionInputFocus()
            monitor.updateEnabled()
        }
        .onChange(of: approvalBridge.pendingQuestions.count) { _, _ in
            updateQuestionInputFocus()
        }
        .onDisappear { releaseQuestionInputFocus() }
    }

    private func approvalCard(_ request: ClaudeApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(request.source.rawValue) permission · \(request.projectName)")
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
                Text(statusLabel(for: session))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(session.lastActivity, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if let prompt = session.latestPrompt {
                Text("You: \(prompt)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if let reply = session.latestReply {
                Text("Reply: \(reply)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if session.status == .working, let tool = session.currentTool {
                Text("Using \(tool)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                if focusService.hasBinding(for: session) {
                    Button(session.isDesktopSession ? "Open session"
                           : focusService.hasExplicitBinding(for: session)
                           ? "Return to terminal" : "Find terminal") {
                        focusService.focus(session)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                }
                if !session.isDesktopSession && focusService.canBindCurrentTerminal {
                    Button("Bind previous terminal") {
                        focusService.bindLastTerminal(to: session)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                }
            }
            if let error = focusService.errorMessage {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func updateQuestionInputFocus() {
        guard !approvalBridge.pendingQuestions.isEmpty,
              let appDelegate = NSApp.delegate as? AppDelegate,
              let window = (vm.screenUUID.flatMap { appDelegate.windows[$0] } ?? appDelegate.window)
                as? BoringNotchSkyLightWindow else {
            releaseQuestionInputFocus()
            return
        }
        if questionWindow !== window {
            releaseQuestionInputFocus()
        }
        questionWindow = window
        window.wantsKeyForTextInput = true
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        window.makeKeyAndOrderFront(nil)
    }

    private func statusLabel(for session: AISessionRecord) -> String {
        let rawID = session.id.split(separator: ":", maxSplits: 1).last.map(String.init)
        if approvalBridge.pendingQuestions.contains(where: {
            $0.source == session.source && $0.sessionID == rawID
        }) { return "Question" }
        if approvalBridge.pending.contains(where: {
            $0.source == session.source && $0.sessionID == rawID
        }) { return "Approval" }
        return session.status.rawValue
    }

    private func releaseQuestionInputFocus() {
        questionWindow?.makeFirstResponder(nil)
        questionWindow?.wantsKeyForTextInput = false
        questionWindow = nil
    }
}

private struct ClaudeQuestionCard: View {
    let request: ClaudeQuestionRequest
    let onAnswer: ([String: String]) -> Void
    let onFallback: () -> Void

    @State private var selected: [String: Set<String>] = [:]
    @State private var customAnswers: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Question from \(request.source.rawValue) · \(request.projectName)")
                .font(.system(size: 11, weight: .semibold))

            ForEach(request.questions) { question in
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.text)
                        .font(.system(size: 11, weight: .medium))
                    ForEach(question.options) { option in
                        Button {
                            choose(option.label, for: question)
                        } label: {
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: selected[question.text, default: []].contains(option.label)
                                    ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                    if let detail = option.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                    }
                    TextField("Other answer", text: customBinding(for: question.text))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))
                }
            }

            HStack {
                Button("Send answers") { onAnswer(answers) }
                    .disabled(answers.count != request.questions.count)
                Button(request.source == .claude ? "Answer in Claude" : "Answer in OpenClaw") {
                    onFallback()
                }
            }
            .font(.system(size: 10, weight: .medium))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
    }

    private var answers: [String: String] {
        var result: [String: String] = [:]
        for question in request.questions {
            let labels = question.options.map(\.label)
                .filter { selected[question.text, default: []].contains($0) }
            let custom = customAnswers[question.text, default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let values = question.multiSelect ? labels + (custom.isEmpty ? [] : [custom])
                : (custom.isEmpty ? Array(labels.prefix(1)) : [custom])
            if !values.isEmpty {
                result[question.text] = values.joined(separator: ", ")
            }
        }
        return result
    }

    private func choose(_ label: String, for question: ClaudeQuestion) {
        if question.multiSelect {
            if selected[question.text, default: []].contains(label) {
                selected[question.text, default: []].remove(label)
            } else {
                selected[question.text, default: []].insert(label)
            }
        } else {
            selected[question.text] = [label]
            customAnswers[question.text] = ""
        }
    }

    private func customBinding(for question: String) -> Binding<String> {
        Binding(
            get: { customAnswers[question, default: ""] },
            set: { customAnswers[question] = $0 }
        )
    }
}
