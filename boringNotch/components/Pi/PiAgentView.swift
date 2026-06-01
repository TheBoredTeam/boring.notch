//
//  PiAgentView.swift
//  boringNotch
//
//  The expanded Pi tab: a multiline prompt field, a live activity line (status word +
//  thinking bars), tool chips that resolve forming → running → ✓, and the streamed
//  answer in a panel that grows with its content.
//

import SwiftUI

struct PiAgentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var pi = PiAgentManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var promptFocused: Bool
    var logoNamespace: Namespace.ID

    /// Presentation height of the answer ScrollView's viewport (what it's allocated).
    @State private var scrollViewportHeight: CGFloat = 0
    /// Natural height of the transcript content inside the ScrollView (incl. footer).
    @State private var transcriptContentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            activityLine
            if !pi.chips.isEmpty || pi.isForming {
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
        }
        // canBecomeKey (typing) follows the field's focus. Staying-open is governed
        // by the session pin alone (checked in ContentView's un-hover paths) — draft
        // text and running tasks no longer hold the panel open.
        .onChange(of: promptFocused) { _, focused in
            SharingStateManager.shared.setKeyboardFocusHeld(focused)
        }
        .onDisappear {
            SharingStateManager.shared.setKeyboardFocusHeld(false)
            // Leaving the tab / closing the panel is a deliberate close — clear the pin.
            pi.piPinned = false
        }
        .notchKeyboardFocus(promptFocused) // makes the window key while the field is focused
    }

    // MARK: Header (logo + prompt + pin + send/stop)

    private var header: some View {
        HStack(alignment: .bottom, spacing: 8) {
            logo
                .frame(width: 24, height: 24)
                .matchedGeometryEffect(id: "piLogo", in: logoNamespace)

            TextField("Ask Pi anything…", text: $pi.draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($promptFocused)
                .notchAcceptsFirstMouse()
                .onSubmit(submit)
                // ⇧↵ inserts a newline; plain ↵ falls through to onSubmit (send).
                // (Option+↵ also inserts a newline natively in vertical-axis fields.)
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    pi.draft += "\n"
                    return .handled
                }

            pinButton

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
                .help("Send (↵) — ⇧↵ for a new line")
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

    /// Session pin: keeps the panel open across mouse-away while engaged. Runtime
    /// only — swipe-up, tab switch, and panel close all clear it (deliberate close
    /// beats pin).
    private var pinButton: some View {
        Button {
            withAnimation(Motion.resolved(Motion.hover, reduceMotion: reduceMotion)) {
                pi.piPinned.toggle()
            }
        } label: {
            Image(systemName: pi.piPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(pi.piPinned ? 1 : 0.85))
                .contentTransition(.symbolEffect(.replace))
                .padding(6)
                .background(
                    Circle().fill(pi.piPinned ? Color.effectiveAccent : Color.white.opacity(0.12))
                )
                .shadow(color: pi.piPinned ? Color.effectiveAccent.opacity(0.55) : .clear, radius: 5)
        }
        .buttonStyle(PiPressButtonStyle(reduceMotion: reduceMotion))
        .help(pi.piPinned ? "Unpin — panel collapses on mouse-away" : "Pin open")
        .accessibilityLabel(pi.piPinned ? "Unpin panel" : "Pin panel open")
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
                Group {
                    if pi.isForming {
                        PiShimmerText(
                            text: activityText,
                            baseColor: .gray,
                            active: true,
                            font: .system(size: 11, weight: .medium, design: .rounded)
                        )
                    } else {
                        Text(activityText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(statusColor)
                    }
                }
                .id(activityText)
                .transition(Motion.transition(Motion.textSwap, reduceMotion: reduceMotion))
                .accessibilityLabel("Status: \(activityText)")
                PiThinkingBarsView(isActive: pi.isRunning)
            }
        }
        .frame(height: 14)
        .animation(Motion.resolved(Motion.textSwapIn, reduceMotion: reduceMotion), value: activityText)
    }

    /// Forming tool ("Send email…" shimmer) → executing tool ("Send email") →
    /// status word ("thinking"/"done"/"aborted").
    private var activityText: String {
        if pi.isForming { return pi.formingToolPretty ?? "Calling a tool…" }
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
                // A tool the model is still forming (arguments streaming) — shimmer
                // label, no spinner. Replaced by the real chip at tool_start.
                if pi.isForming {
                    formingChip
                        .transition(Motion.transition(Motion.overlay, reduceMotion: reduceMotion))
                }
                ForEach(pi.chips) { chip in
                    PiToolChipView(chip: chip, reduceMotion: reduceMotion)
                        .transition(Motion.transition(Motion.overlay, reduceMotion: reduceMotion))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
        .animation(Motion.resolved(Motion.shelfItemEnter, reduceMotion: reduceMotion), value: pi.chips)
        .animation(Motion.resolved(Motion.shelfItemEnter, reduceMotion: reduceMotion), value: pi.isForming)
    }

    private var formingChip: some View {
        HStack(spacing: 5) {
            // Same fixed icon slot as the real chip so the label lands at the same x
            // when the chip resolves at tool_start.
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 5, height: 5)
                .frame(width: 11, height: 11)

            PiShimmerText(
                text: pi.formingToolPretty ?? "Calling a tool…",
                baseColor: .white.opacity(0.9),
                active: true,
                font: .system(size: 10, weight: .medium, design: .monospaced)
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(
            Capsule().fill(Color.white.opacity(0.05))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pi.formingToolPretty ?? "Tool"), preparing")
    }

    // MARK: Answer

    private var answer: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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

                    // Comfort footer: keeps the newest line off the panel's bottom edge;
                    // the auto-scroll anchor rides on it.
                    Color.clear
                        .frame(height: 28)
                        .id("piTranscriptBottom")
                }
                .background(heightReader(into: $transcriptContentHeight))
            }
            .background(heightReader(into: $scrollViewportHeight))
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
        .onChange(of: transcriptContentHeight) { _, _ in reportDesiredHeight() }
        .onChange(of: scrollViewportHeight) { _, _ in reportDesiredHeight() }
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

    // MARK: Content-height reporting

    /// GeometryReader+PreferenceKey height probe (deployment target is macOS 14, so
    /// no `onGeometryChange`).
    private func heightReader(into binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: PiContentHeightKey.self, value: geo.size.height)
                .onPreferenceChange(PiContentHeightKey.self) { height in
                    binding.wrappedValue = height
                }
        }
    }

    /// Tell the view model how tall the open panel wants to be: the current panel
    /// height with the answer's viewport swapped for its content's natural height.
    /// BoringViewModel clamps this into [base, expanded] — the panel grows with the
    /// answer (no inner scrolling) until the cap, where the ScrollView takes over.
    private func reportDesiredHeight() {
        guard scrollViewportHeight > 0 else { return }
        let desired = (vm.openPanelHeight - scrollViewportHeight + transcriptContentHeight).rounded()
        if abs(pi.measuredContentHeight - desired) >= 1 {
            pi.measuredContentHeight = desired
        }
    }

    // MARK: Actions

    private func submit() {
        let text = pi.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pi.send(text)
        pi.draft = ""
    }
}

/// Reports a view's laid-out height up the tree (transcript content / scroll viewport).
private struct PiContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(Motion.resolved(Motion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
