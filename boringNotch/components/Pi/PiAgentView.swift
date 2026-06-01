//
//  PiAgentView.swift
//  boringNotch
//
//  The expanded Pi tab: a prompt field, a live activity line (status word +
//  thinking bars), tool chips that resolve running → ✓, and the streamed answer.
//

import Defaults
import SwiftUI

struct PiAgentView: View {
    @ObservedObject var pi = PiAgentManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var promptFocused: Bool
    @Default(.piExpanded) private var piExpanded
    var logoNamespace: Namespace.ID

    /// Hold the notch open only while there's unsent text or a run is active —
    /// independent of keyboard focus AND of the expand state, so an expanded tab is
    /// NOT pinned: mouse-away collapses it like any other tab, and the chevron simply
    /// toggles the panel size (which persists). This is the "unpin" the user asked
    /// for — expanding no longer traps the notch open.
    private var shouldHold: Bool {
        !pi.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || pi.isRunning
    }

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
        .onAppear {
            promptFocused = true                                          // instant typing
            SharingStateManager.shared.setKeyboardFocusHeld(true)         // let the window become key
            SharingStateManager.shared.setHoldOpen(shouldHold)            // close-prevention reasons
        }
        // canBecomeKey (typing) follows the field's focus…
        .onChange(of: promptFocused) { _, focused in
            SharingStateManager.shared.setKeyboardFocusHeld(focused)
        }
        // …while staying-open is gated only on unsent text / a running task (not focus, not expand).
        .onChange(of: pi.draft) { _, _ in SharingStateManager.shared.setHoldOpen(shouldHold) }
        .onChange(of: pi.isRunning) { _, _ in SharingStateManager.shared.setHoldOpen(shouldHold) }
        .onDisappear {
            SharingStateManager.shared.setKeyboardFocusHeld(false)
            SharingStateManager.shared.setHoldOpen(false)
        }
        .notchKeyboardFocus(promptFocused) // makes the window key while the field is focused
    }

    // MARK: Header (logo + prompt + chevron + send/stop)

    private var header: some View {
        HStack(spacing: 8) {
            logo
                .frame(width: 24, height: 24)
                .matchedGeometryEffect(id: "piLogo", in: logoNamespace)

            TextField("Ask Pi anything…", text: $pi.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($promptFocused)
                .notchAcceptsFirstMouse()
                .onSubmit(submit)

            expandButton

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
                .disabled(pi.draft.trimmingCharacters(in: .whitespaces).isEmpty)
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

    /// Chevron toggle: compact ↔ expanded. Pins the tab open while expanded and
    /// persists the choice (Defaults). The window resize is driven separately by
    /// `AppDelegate.observePiExpansion`.
    private var expandButton: some View {
        Button {
            withAnimation(Motion.resolved(Motion.hover, reduceMotion: reduceMotion)) {
                piExpanded.toggle()
            }
        } label: {
            Image(systemName: piExpanded ? "chevron.down.chevron.up" : "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .contentTransition(.symbolEffect(.replace))
                .padding(6)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(PiPressButtonStyle(reduceMotion: reduceMotion))
        .help(piExpanded ? "Collapse" : "Expand")
    }

    /// Logo precedence: (1) live per-toolkit CDN metadata logo, (2) the bundled
    /// Composio mark as the persistent default, (3) `sparkles` only if the asset is
    /// missing. Never blank.
    @ViewBuilder
    private var logo: some View {
        if let image = pi.toolkitLogo {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if let composio = NSImage(named: "composio-mark") {
            Image(nsImage: composio)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white.opacity(0.92))
                .padding(2)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(Color.effectiveAccent)
        }
    }

    // MARK: Activity line

    private var activityLine: some View {
        HStack(spacing: 7) {
            if pi.isRunning || pi.statusWord == "done" || pi.statusWord == "aborted" {
                Text(activityText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(statusColor)
                    .contentTransition(.opacity)
                    .accessibilityLabel("Status: \(activityText)")
                PiThinkingBarsView(isActive: pi.isRunning)
            }
        }
        .frame(height: 14)
        .animation(Motion.resolved(Motion.flash, reduceMotion: reduceMotion), value: activityText)
    }

    /// Prefer the sanitized current tool name during a run ("Send email"), falling
    /// back to the status word ("thinking"/"done"/"aborted").
    private var activityText: String {
        if pi.isRunning, let pretty = pi.currentToolPretty { return pretty }
        return pi.statusWord.isEmpty ? "thinking" : pi.statusWord
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
            HStack(spacing: 8) {
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
                Group {
                    if pi.transcript.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 12))
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        PiMarkdownView(text: pi.transcript)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("piTranscriptBottom")
            }
            .scrollIndicators(.visible)
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
        let text = pi.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pi.send(text)
        pi.draft = ""
    }
}

// MARK: - Tool chip

private struct PiToolChipView: View {
    let chip: ToolChip
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 5) {
            // Fixed icon slot so the label sits at the same x whether the chip is
            // spinning or resolved (no horizontal jump on tool_end).
            Group {
                if chip.running {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.62)
                } else {
                    Image(systemName: chip.ok == false ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(chip.ok == false ? .red : .green)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 11, height: 11)

            Text(chip.tool)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
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
