//
//  AgentNotificationCard.swift
//  boringNotch
//
//  The in-notch action surface: when Claude needs a decision the notch
//  expands (see ContentView) and this view renders the top-priority card —
//  permission approvals with green/red actions, agent questions with
//  tappable options (single or multi select), and "done" replies with a
//  quick-reply box. No floating windows involved.
//

import SwiftUI
import Defaults

// MARK: - Root surface (picks the top-priority card)

struct AgentApprovalView: View {
    @ObservedObject private var vm = AIAgentViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            if let question = vm.activeQuestion {
                AgentQuestionCard(question: question)
            } else if let permission = vm.activePermission {
                AgentPermissionCard(permission: permission)
            } else if let done = vm.activeDoneCard {
                AgentDoneCardView(card: done)
            } else {
                AgentAllClearView()
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared card chrome

private struct AgentCardChrome<Content: View>: View {
    let tint: Color
    let icon: String
    let title: String
    let subtitle: String
    var onDismiss: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AgentPalette.paper)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(AgentPalette.paperSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AgentPalette.paperFaint)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss (falls back to the terminal prompt)")
                }
            }

            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
}

// MARK: - Permission card

struct AgentPermissionCard: View {
    @ObservedObject private var vm = AIAgentViewModel.shared
    let permission: AgentPendingPermission

    var body: some View {
        AgentCardChrome(
            tint: AgentPalette.waiting,
            icon: "hand.raised.fill",
            title: "Claude needs permission",
            subtitle: subtitleText,
            onDismiss: { vm.dismissCard(permission.id) }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if !permission.detail.isEmpty {
                    Text(permission.detail)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(AgentPalette.paper.opacity(0.88))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                        )
                }

                HStack(spacing: 10) {
                    Button {
                        vm.deny(permission: permission)
                    } label: {
                        Label("Deny", systemImage: "xmark")
                    }
                    .buttonStyle(AgentPrimaryButtonStyle(tint: AgentPalette.waitingApproval))
                    .keyboardShortcut(.cancelAction)

                    Button("Always allow") {
                        vm.approve(permission: permission, always: true)
                    }
                    .buttonStyle(AgentSecondaryButtonStyle())

                    Spacer()

                    Button {
                        vm.approve(permission: permission)
                    } label: {
                        Label("Approve", systemImage: "checkmark")
                    }
                    .buttonStyle(AgentPrimaryButtonStyle(tint: AgentPalette.completed))
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var subtitleText: String {
        var parts = [permission.title]
        if let dir = permission.directory, !dir.isEmpty {
            parts.append((dir as NSString).lastPathComponent)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Question card

struct AgentQuestionCard: View {
    @ObservedObject private var vm = AIAgentViewModel.shared
    let question: AgentPendingQuestion

    // Selection mode (multi-select options or several questions)
    @State private var selections: [String: Set<String>] = [:]
    @State private var customText = ""
    @State private var submitting = false

    /// Selection mode: several questions, or the question allows multiple picks.
    private var needsSelection: Bool {
        question.questions.count > 1 || question.questions.contains { $0.multiple }
    }

    var body: some View {
        AgentCardChrome(
            tint: AgentPalette.waitingAnswer,
            icon: "questionmark.bubble.fill",
            title: titleText,
            subtitle: subtitleText,
            onDismiss: { vm.dismissCard(question.id) }
        ) {
            if needsSelection {
                selectionBody
            } else if let q = question.questions.first {
                instantBody(q)
            }
        }
    }

    // MARK: Instant answer — one question, one pick, tap to send

    @ViewBuilder
    private func instantBody(_ q: AgentQuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(q.options) { option in
                        optionRow(option, questionID: q.id, instant: true)
                    }
                }
                .padding(.vertical, 1)
            }
            if q.options.count <= 5 {
                customField
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Selection mode — pick (possibly several), then confirm

    private var selectionBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if question.questions.count > 1 {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(question.questions) { q in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(q.question)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(AgentPalette.paper.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                                ForEach(q.options) { option in
                                    optionRow(option, questionID: q.id, instant: false)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else if let q = question.questions.first {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(q.options) { option in
                            optionRow(option, questionID: q.id, instant: false)
                        }
                    }
                    .padding(.vertical, 1)
                }
                customField
            }

            HStack(spacing: 10) {
                Button {
                    vm.dismissCard(question.id)
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(AgentSecondaryButtonStyle(tint: AgentPalette.waitingApproval))

                Spacer()

                Button {
                    confirmSelection()
                } label: {
                    Label("Confirm", systemImage: "checkmark")
                }
                .buttonStyle(AgentPrimaryButtonStyle(tint: AgentPalette.completed))
                .disabled(!hasRequiredSelections)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Option row (shared by both modes)

    private func optionRow(_ option: AgentQuestionOption, questionID: String, instant: Bool) -> some View {
        let isSelected = selections[questionID]?.contains(option.label) ?? false

        return Button {
            if instant {
                submit(answers: [[option.label]])
            } else {
                toggle(option.label, questionID: questionID)
            }
        } label: {
            HStack(spacing: 8) {
                if !instant {
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? AgentPalette.completed : Color.white.opacity(0.22),
                                          lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                        if isSelected {
                            Circle()
                                .fill(AgentPalette.completed)
                                .frame(width: 16, height: 16)
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(AgentPalette.ink)
                        }
                    }
                } else {
                    AgentStateDot(color: AgentPalette.paperFaint, pulsing: false, size: 5)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AgentPalette.paper)
                        .lineLimit(1)
                    if !option.detail.isEmpty {
                        Text(option.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(AgentPalette.paperSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AgentPalette.completed.opacity(0.14) : Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? AgentPalette.completed.opacity(0.45) : Color.white.opacity(0.07),
                                      lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(submitting)
    }

    private var customField: some View {
        HStack(spacing: 6) {
            TextField("Other — type your own answer…", text: $customText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(AgentPalette.paper)
                .onSubmit { submitCustom() }
            Button {
                submitCustom()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(customText.isEmpty ? AgentPalette.paperFaint : AgentPalette.completed)
            }
            .buttonStyle(.plain)
            .disabled(customText.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    // MARK: Actions

    private func toggle(_ label: String, questionID: String) {
        let allowsMultiple = question.questions.first { $0.id == questionID }?.multiple ?? false
        var set = selections[questionID] ?? []
        if set.contains(label) {
            set.remove(label)
        } else {
            if !allowsMultiple { set = [] }
            set.insert(label)
        }
        selections[questionID] = set
    }

    private var hasRequiredSelections: Bool {
        question.questions.allSatisfy { q in
            !(selections[q.id] ?? []).isEmpty
        }
    }

    private func confirmSelection() {
        let answers = question.questions.map { q in
            Array((selections[q.id] ?? []).intersection(Set(q.options.map(\.label))))
        }
        submit(answers: answers)
    }

    private func submitCustom() {
        let text = customText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        submit(answers: [[text]])
    }

    private func submit(answers: [[String]]) {
        guard !submitting else { return }
        submitting = true
        vm.answer(question: question, answers: answers)
    }

    private var titleText: String {
        question.questions.first?.header.isEmpty == false
            ? question.questions.first!.header
            : (question.questions.first?.question ?? "Claude asks")
    }

    private var subtitleText: String {
        let q = question.questions.first
        if question.questions.count > 1 {
            return "\(question.questions.count) questions · \(dirName)"
        }
        if let q, q.header.isEmpty == false {
            return q.question
        }
        return dirName
    }

    private var dirName: String {
        question.directory.map { ($0 as NSString).lastPathComponent } ?? "claude"
    }
}

// MARK: - Done card

struct AgentDoneCardView: View {
    @ObservedObject private var vm = AIAgentViewModel.shared
    let card: AgentDoneCard
    @State private var replyText = ""
    @FocusState private var replyFocused: Bool

    var body: some View {
        AgentCardChrome(
            tint: AgentPalette.completed,
            icon: "checkmark.circle.fill",
            title: card.title,
            subtitle: "finished · tap to open",
            onDismiss: { vm.dismissOldestDoneCard() }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(card.reply)
                    .font(.system(size: 12))
                    .foregroundStyle(AgentPalette.paper.opacity(0.9))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.3))
                    )

                HStack(spacing: 10) {
                    Button {
                        openInAgentTab()
                    } label: {
                        Label("Open agent tab", systemImage: "brain")
                    }
                    .buttonStyle(AgentSecondaryButtonStyle())

                    Spacer()

                    quickReply
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openInAgentTab() }
    }

    private var quickReply: some View {
        HStack(spacing: 6) {
            TextField("Quick reply…", text: $replyText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(AgentPalette.paper)
                .focused($replyFocused)
                .onSubmit { sendReply() }
            Button {
                sendReply()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(replyText.isEmpty ? AgentPalette.paperFaint : AgentPalette.completed)
            }
            .buttonStyle(.plain)
            .disabled(replyText.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(replyFocused ? Color.white.opacity(0.18) : Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        replyText = ""
        vm.dismissOldestDoneCard()
        Task {
            vm.openChat(sessionID: card.sessionID)
            await vm.sendPrompt(text)
        }
    }

    private func openInAgentTab() {
        BoringViewCoordinator.shared.currentView = .agent
        vm.openChat(sessionID: card.sessionID)
        vm.dismissOldestDoneCard()
    }
}

// MARK: - All clear

/// Shown when the notch is open on the approval surface but nothing is
/// pending anymore (the notch closes itself in this state).
struct AgentAllClearView: View {
    var body: some View {
        VStack(spacing: 6) {
            AgentStateDot(color: AgentPalette.completed, pulsing: false, size: 8)
            Text("You're all caught up")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AgentPalette.paperSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}