//
//  AgentQuestionCard.swift
//  boringCode
//
//  Responder o AskUserQuestion do Claude Code direto no notch. Mesmo fluxo do
//  StructuredQuestionPromptView do Open Island (github.com/Octane0411/open-vibe-island,
//  GPL-3.0): opções + "Outra" com texto livre; múltiplas respostas unidas por ", ".
//

import SwiftUI

struct AgentQuestionCard: View {
    let sessionID: String
    let pending: AgentPendingQuestion

    @ObservedObject private var store = AgentSessionStore.shared
    @State private var step = 0
    @State private var selections: [String: Set<String>] = [:]
    @State private var otherText: [String: String] = [:]
    @State private var otherActive: Set<String> = []
    @FocusState private var otherFocused: Bool
    @State private var window: NSWindow?

    private var question: AgentQuestion { pending.questions[min(step, pending.questions.count - 1)] }
    private var isLast: Bool { step >= pending.questions.count - 1 }

    private func answer(for question: AgentQuestion) -> String? {
        var parts = question.options.map(\.label).filter { selections[question.id]?.contains($0) == true }
        if otherActive.contains(question.id) {
            let text = (otherText[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { parts.append(text) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if pending.questions.count > 1 {
                    Text("\(step + 1)/\(pending.questions.count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.gray)
                }
                if let header = question.header, !header.isEmpty {
                    Text(header)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                Text(question.question)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AgentFlowLayout(spacing: 6) {
                ForEach(question.options) { option in
                    chip(option.label, selected: selections[question.id]?.contains(option.label) == true) {
                        toggle(option.label)
                    }
                    .help(option.description ?? option.label)
                }
                chip(String(localized: "Other…"), selected: otherActive.contains(question.id)) {
                    toggleOther()
                }
            }

            if otherActive.contains(question.id) {
                TextField("Type your answer", text: Binding(
                    get: { otherText[question.id] ?? "" },
                    set: { otherText[question.id] = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
                .focused($otherFocused)
                .onSubmit(advance)
            }

            HStack {
                Button("Answer in terminal") { store.answerInTerminal(sessionID) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                Spacer()
                Button(action: advance) {
                    Text(isLast ? "Send" : "Next")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .foregroundStyle(.black)
                        .background(Capsule().fill(Color.white))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(answer(for: question) == nil)
                .opacity(answer(for: question) == nil ? 0.4 : 1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .background(WindowReader(window: $window))
        .onChange(of: otherFocused) { _, focused in setTextInput(focused) }
        .onDisappear { setTextInput(false) }
        .onChange(of: pending.id) { _, _ in
            step = 0; selections = [:]; otherText = [:]; otherActive = []
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(label)
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(selected ? .black : .white)
            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ label: String) {
        var current = selections[question.id] ?? []
        if question.multiSelect {
            if current.contains(label) { current.remove(label) } else { current.insert(label) }
        } else {
            current = current.contains(label) ? [] : [label]
            otherActive.remove(question.id)
        }
        selections[question.id] = current
    }

    private func toggleOther() {
        if otherActive.contains(question.id) {
            otherActive.remove(question.id)
            otherFocused = false
        } else {
            otherActive.insert(question.id)
            if !question.multiSelect { selections[question.id] = [] }
            DispatchQueue.main.async { otherFocused = true }
        }
    }

    private func advance() {
        guard answer(for: question) != nil else { return }
        if isLast {
            var answers: [String: String] = [:]
            for question in pending.questions {
                if let value = answer(for: question) { answers[question.question] = value }
            }
            setTextInput(false)
            store.answer(sessionID, answers: answers)
        } else {
            otherFocused = false
            step += 1
        }
    }

    /// O painel do notch só aceita teclado enquanto um campo está sendo usado.
    private func setTextInput(_ enabled: Bool) {
        (window as? BoringNotchSkyLightWindow)?.wantsKeyForTextInput = enabled
    }
}

/// Descobre a NSWindow onde a view está.
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if window !== nsView.window {
            DispatchQueue.main.async { window = nsView.window }
        }
    }
}

/// Quebra os chips em linhas conforme a largura disponível.
struct AgentFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
