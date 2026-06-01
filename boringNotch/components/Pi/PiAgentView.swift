//
//  PiAgentView.swift
//  boringNotch
//
//  The expanded Pi tab: a prompt field, a live activity line (status word +
//  thinking bars), tool chips that resolve running → ✓, and the streamed answer.
//

import SwiftUI

struct PiAgentView: View {
    @ObservedObject var pi = PiAgentManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var promptFocused: Bool
    @State private var prompt: String = ""
    var logoNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            activityLine
            if !pi.chips.isEmpty {
                chipsRow
            }
            answer
            if let error = pi.lastError {
                errorRow(error)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { promptFocused = true }
        .onChange(of: promptFocused) { _, focused in
            // Don't let the notch collapse out from under the keyboard while typing.
            SharingStateManager.shared.preventNotchClose = focused
        }
        .onDisappear { SharingStateManager.shared.preventNotchClose = false }
    }

    // MARK: Header (logo + prompt + send/stop)

    private var header: some View {
        HStack(spacing: 8) {
            logo
                .frame(width: 24, height: 24)
                .matchedGeometryEffect(id: "piLogo", in: logoNamespace)

            TextField("Ask Pi anything…", text: $prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($promptFocused)
                .onSubmit(submit)

            if pi.isRunning {
                Button(action: pi.abort) {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(Color.red.opacity(0.85)))
                }
                .buttonStyle(PiPressButtonStyle(reduceMotion: reduceMotion))
                .keyboardShortcut(".", modifiers: .command)
                .help("Stop (⌘.)")
                .transition(.opacity)
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(Color.effectiveAccent))
                }
                .buttonStyle(PiPressButtonStyle(reduceMotion: reduceMotion))
                .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Send (↵)")
                .transition(.opacity)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .animation(Motion.resolved(Motion.hover, reduceMotion: reduceMotion), value: pi.isRunning)
    }

    @ViewBuilder
    private var logo: some View {
        if let image = pi.toolkitLogo {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(Color.effectiveAccent)
        }
    }

    // MARK: Activity line

    private var activityLine: some View {
        HStack(spacing: 6) {
            if pi.isRunning || pi.statusWord == "done" || pi.statusWord == "aborted" {
                Text(pi.statusWord.isEmpty ? "thinking" : pi.statusWord)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(statusColor)
                    .contentTransition(.opacity)
                    .accessibilityLabel("Status: \(pi.statusWord)")
                PiThinkingBarsView(isActive: pi.isRunning)
            }
        }
        .frame(height: 14)
        .animation(Motion.resolved(Motion.flash, reduceMotion: reduceMotion), value: pi.statusWord)
    }

    private var statusColor: Color {
        switch pi.statusWord {
        case "done": return .green
        case "aborted": return .orange
        default: return .gray
        }
    }

    // MARK: Chips

    private var chipsRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(pi.chips) { chip in
                    PiToolChipView(chip: chip, reduceMotion: reduceMotion)
                        .transition(Motion.transition(Motion.overlay, reduceMotion: reduceMotion))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
        .animation(Motion.resolved(Motion.shelfItemEnter, reduceMotion: reduceMotion), value: pi.chips)
    }

    // MARK: Answer

    private var answer: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(pi.transcript.isEmpty ? placeholder : pi.transcript)
                    .font(.system(size: 12))
                    .foregroundStyle(pi.transcript.isEmpty ? .gray : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .id("piTranscriptBottom")
            }
            .onChange(of: pi.transcript) { _, _ in
                withAnimation(Motion.resolved(.easeOut(duration: 0.18), reduceMotion: reduceMotion)) {
                    proxy.scrollTo("piTranscriptBottom", anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var placeholder: String {
        pi.isRunning ? "" : "Pi’s answer will stream here."
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pi.send(text)
        prompt = ""
    }
}

// MARK: - Tool chip

private struct PiToolChipView: View {
    let chip: ToolChip
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 4) {
            if chip.running {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: chip.ok == false ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(chip.ok == false ? .red : .green)
                    .contentTransition(.symbolEffect(.replace))
            }
            Text(chip.tool)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.white.opacity(0.08))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chip.tool), \(chip.running ? "running" : (chip.ok == false ? "failed" : "done"))")
    }
}

// MARK: - Press style

private struct PiPressButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.resolved(Motion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
