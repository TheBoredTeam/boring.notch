//
//  PiAgentView.swift
//  boringNotch
//
//  The expanded Pi tab: a multiline prompt field, a live activity line (status word +
//  thinking bars), tool chips that resolve forming → running → ✓, and the streamed
//  answer in a panel that grows with its content.
//

import AppKit
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
    /// Stick-to-bottom: true while the answer view follows the streamed tail. Broken
    /// by the user scrolling up to read; restored when they scroll back to the bottom
    /// or a new turn starts. Never broken by content growth itself.
    @State private var isFollowingTail = true
    /// The transcript's top edge within the answer scroll view's coordinate space
    /// (0 at rest, decreasing as the user scrolls down). Drives user-scroll detection.
    @State private var transcriptScrollMinY: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            activityLine
            if !pi.chips.isEmpty || pi.isForming {
                chipsRow
                    .transition(Motion.transition(Motion.overlay, reduceMotion: reduceMotion))
            }
            answer
            if let error = pi.lastError {
                errorRow(error)
                    .transition(Motion.transition(Motion.overlay, reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Rows appearing/leaving (chips, error) settle in with the shared item spring
        // instead of popping — the layout shift underneath them animates as one unit.
        .animation(Motion.resolved(Motion.shelfItemEnter, reduceMotion: reduceMotion), value: !pi.chips.isEmpty || pi.isForming)
        .animation(Motion.resolved(Motion.hover, reduceMotion: reduceMotion), value: pi.lastError)
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
        HStack(alignment: .center, spacing: 7) {
            logo
                // Tighter than before (was 24): a smaller textbox leaves more headroom
                // for the tab switcher above, and the mark sits closer to the peek's
                // slot size so the matchedGeometry morph travels less.
                .frame(width: 20, height: 20)
                .matchedGeometryEffect(id: "piLogo", in: logoNamespace)

            TextField("Ask Pi anything…", text: $pi.draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($promptFocused)
                .notchAcceptsFirstMouse()
                // ↵ and ⌘↵ both send; Option+↵ inserts a newline.
                // (Option+↵ inserts a newline natively in vertical-axis fields —
                // at the cursor, so let it through untouched.)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.option) { return .ignored }
                    submit()
                    return .handled
                }

            pinButton

            // Send ⇄ stop swap rides Motion.overlay (scale from 0.92 + fade) — the
            // incoming button never appears from nothing.
            if pi.isRunning {
                Button(action: pi.abort) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(Color.red.opacity(0.85)))
                }
                .buttonStyle(PressStyle(reduceMotion: reduceMotion))
                .keyboardShortcut(".", modifiers: .command)
                .help("Stop (⌘.)")
                .transition(Motion.transition(Motion.overlay, reduceMotion: reduceMotion))
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(Color.effectiveAccent))
                }
                .buttonStyle(PressStyle(reduceMotion: reduceMotion))
                .disabled(pi.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send (↵ or ⌘↵) — ⌥↵ for a new line")
                .transition(Motion.transition(Motion.overlay, reduceMotion: reduceMotion))
            }
        }
        // Slimmer vertical padding (was a uniform 8) is the bulk of the height saving;
        // horizontal stays 8 so the field isn't cramped side-to-side.
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
                // Focus ring: an accent hairline blooms in when the field is focused,
                // so the textbox visibly "hears" the cursor. Eased, transform/opacity-free.
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.effectiveAccent.opacity(promptFocused ? 0.45 : 0), lineWidth: 1)
                )
        )
        .animation(Motion.resolved(Motion.hover, reduceMotion: reduceMotion), value: pi.isRunning)
        .animation(Motion.resolved(Motion.hover, reduceMotion: reduceMotion), value: promptFocused)
    }

    /// Session pin: keeps the panel open across mouse-away and makes swipe-up inert,
    /// so reading/scrolling a streamed answer can never dismiss the panel. Runtime
    /// only — unpin, tab switch, and panel close clear it.
    private var pinButton: some View {
        Button {
            withAnimation(Motion.resolved(Motion.hover, reduceMotion: reduceMotion)) {
                pi.piPinned.toggle()
            }
        } label: {
            Image(systemName: pi.piPinned ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(pi.piPinned ? 1 : 0.85))
                .contentTransition(.symbolEffect(.replace))
                .padding(5)
                .background(
                    Circle().fill(pi.piPinned ? Color.effectiveAccent : Color.white.opacity(0.12))
                )
                .shadow(color: pi.piPinned ? Color.effectiveAccent.opacity(0.55) : .clear, radius: 5)
        }
        .buttonStyle(PressStyle(reduceMotion: reduceMotion))
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
            let _ = (composio.isTemplate = true)   // force AppKit template mask → tints to foregroundStyle
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
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    // Resolved tool chips, oldest → newest (left → right; chips.append).
                    ForEach(pi.chips) { chip in
                        PiToolChipView(chip: chip, reduceMotion: reduceMotion)
                            .transition(Motion.transition(Motion.overlay, reduceMotion: reduceMotion))
                    }
                    // The tool still forming sits at the *trailing* (newest) end — the same
                    // slot the resolved chip lands in when it appends, so it swaps in place
                    // (the leading position it used to occupy made the swap jump the row).
                    if pi.isForming {
                        formingChip
                            .transition(Motion.transition(Motion.overlay, reduceMotion: reduceMotion))
                    }
                    // Scroll anchor: keeps the live activity in view as chips overflow.
                    Color.clear.frame(width: 1, height: 1).id(Self.chipsTailID)
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            .animation(Motion.resolved(Motion.shelfItemEnter, reduceMotion: reduceMotion), value: pi.chips)
            .animation(Motion.resolved(Motion.shelfItemEnter, reduceMotion: reduceMotion), value: pi.isForming)
            // Follow the newest chip / forming label as the row grows past the viewport.
            .onChange(of: pi.chips.count) { _, _ in scrollChipsToTail(proxy) }
            .onChange(of: pi.isForming) { _, forming in if forming { scrollChipsToTail(proxy) } }
        }
    }

    private static let chipsTailID = "piChipsTail"

    private func scrollChipsToTail(_ proxy: ScrollViewProxy) {
        withAnimation(Motion.resolved(Motion.shelfItemEnter, reduceMotion: reduceMotion)) {
            proxy.scrollTo(Self.chipsTailID, anchor: .trailing)
        }
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
        let shown = pi.transcript
        // Trim before deciding emptiness: a connection-blocked turn often leaves only
        // whitespace (the model wrote nothing but the stripped deeplink), which would
        // otherwise render as an invisible non-empty answer — a blank box with no
        // placeholder. Treating whitespace as empty surfaces the placeholder/guidance.
        let isBlank = shown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        if isBlank {
                            Text(placeholder)
                                .font(.system(size: 12))
                                .foregroundStyle(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        } else if pi.isRunning || !MDBlock.hasBlockStructure(shown) {
                            // Streaming, or settled-but-plain prose: one inline Text.
                            // Never reflows mid-stream (the common case) and avoids
                            // per-delta re-parse of unclosed fences/lists.
                            PiInlineText(text: shown)
                                .transition(.opacity)
                        } else {
                            // Settled and block-structured: full markdown layout. A
                            // structured answer flips inline→block once at settle.
                            PiMarkdownView(text: shown)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Placeholder → first content is a crossfade, not a hard swap.
                    .animation(Motion.resolved(Motion.hover, reduceMotion: reduceMotion), value: isBlank)
                    // Smooth single inline→block crossfade once the run settles.
                    .animation(Motion.resolved(Motion.hover, reduceMotion: reduceMotion), value: pi.isRunning)

                    // Comfort footer: keeps the newest line off the panel's bottom edge;
                    // the auto-scroll anchor rides on it.
                    Color.clear
                        .frame(height: 28)
                        .id("piTranscriptBottom")
                }
                .background(heightReader(into: $transcriptContentHeight))
                .background(scrollPositionReader)
            }
            .coordinateSpace(name: Self.answerScrollSpace)
            .background(heightReader(into: $scrollViewportHeight))
            // .automatic: a thin overlay scroller that fades in only while scrolling,
            // instead of the heavy always-on rail .visible pins down the panel's edge.
            .scrollIndicators(.automatic)
            .onChange(of: transcriptScrollMinY) { oldY, newY in
                updateTailFollowing(oldMinY: oldY, newMinY: newY)
            }
            .onChange(of: pi.transcript) { _, _ in
                // Stick-to-bottom: follow the stream only while the user is at the
                // tail. Unanimated on purpose — deltas land many times a second, and
                // an animated scroll restarted on every token perpetually lags and
                // rubber-bands. Instant tracking reads as the content simply growing.
                guard isFollowingTail else { return }
                proxy.scrollTo("piTranscriptBottom", anchor: .bottom)
            }
            .onChange(of: pi.isRunning) { _, running in
                // A new turn always rejoins the tail.
                guard running else { return }
                isFollowingTail = true
                proxy.scrollTo("piTranscriptBottom", anchor: .bottom)
            }
        }
        // minHeight floors the viewport so the chrome rows can never starve it to zero;
        // layoutPriority gives the flexible answer first claim on space over the fixed
        // chrome rows.
        .frame(maxWidth: .infinity, minHeight: Self.answerMinViewportHeight, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .onChange(of: transcriptContentHeight) { _, _ in reportDesiredHeight() }
        .onChange(of: scrollViewportHeight) { _, _ in reportDesiredHeight() }
    }

    // MARK: Stick-to-bottom scroll tracking

    /// Coordinate space of the answer ScrollView (scroll-position probe reads against it).
    private static let answerScrollSpace = "piAnswerScroll"

    /// Floor for the answer ScrollView's viewport. Chrome rows (header, activity line,
    /// chips) are fixed-size and stack above the answer; when enough of them appear they
    /// could otherwise starve the flexible answer to a zero-height viewport. A non-zero
    /// floor guarantees the viewport never collapses, which keeps the
    /// content-drives-panel height loop (`reportDesiredHeight`) alive — a zero viewport
    /// used to deadlock panel growth so the answer stayed invisible.
    private static let answerMinViewportHeight: CGFloat = 72

    /// Within this distance of the bottom the user counts as "at the tail" — generous
    /// enough to absorb the comfort footer and sub-line scroll positions.
    private static let tailRejoinDistance: CGFloat = 44
    /// An upward scroll must leave at least this much content below the viewport
    /// before following breaks — keeps bottom rubber-band bounces from unsticking.
    private static let tailBreakDistance: CGFloat = 8

    /// How much content currently sits below the viewport's bottom edge.
    private var distanceFromBottom: CGFloat {
        transcriptContentHeight - scrollViewportHeight + transcriptScrollMinY
    }

    /// Stick-to-bottom bookkeeping. Content growth never breaks following (streaming
    /// pushes the bottom away without the user touching anything — minY is unchanged);
    /// only an actual upward scroll does. Scrolling back to the bottom rejoins the tail.
    private func updateTailFollowing(oldMinY: CGFloat, newMinY: CGFloat) {
        if newMinY > oldMinY + 0.5 {
            // Content moved down ⇒ the user scrolled up.
            if distanceFromBottom > Self.tailBreakDistance {
                isFollowingTail = false
            }
        } else if distanceFromBottom <= Self.tailRejoinDistance {
            // The user scrolled back down to the tail.
            isFollowingTail = true
        }
    }

    /// Reports the transcript's top edge within the answer ScrollView (scroll position).
    private var scrollPositionReader: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: PiScrollMinYKey.self,
                    value: geo.frame(in: .named(Self.answerScrollSpace)).minY
                )
                .onPreferenceChange(PiScrollMinYKey.self) { minY in
                    transcriptScrollMinY = minY
                }
        }
    }

    private var placeholder: String {
        if pi.isRunning { return "" }
        return "Pi’s answer will stream here."
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
    ///
    /// Uses the panel's *laid-out* height (vm.laidOutPanelHeight), never the target
    /// (vm.openPanelHeight): while the open spring / tab transition is animating, the
    /// viewport is mid-flight and the target has already jumped, so mixing them
    /// produced garbage that fed back into the height pipeline and thrashed the panel.
    /// Laid-out panel = chrome + laid-out viewport at every animation frame, so this
    /// difference — and therefore `desired` — stays stable while the panel animates.
    private func reportDesiredHeight() {
        // Floor the viewport instead of bailing on zero. A hard `guard viewportHeight > 0`
        // here used to deadlock: when chrome starved the answer to a zero-height viewport,
        // this returned early and the panel never grew to reveal the answer. The answer
        // ScrollView now carries the same floor, so a realized viewport is always ≥ it;
        // flooring the pre-layout zero keeps `panelHeight - viewport` (the chrome height)
        // from over-counting on the first frame.
        let viewport = max(scrollViewportHeight, Self.answerMinViewportHeight)
        let panelHeight = vm.laidOutPanelHeight > 0 ? vm.laidOutPanelHeight : vm.openPanelHeight
        let desired = (panelHeight - viewport + transcriptContentHeight).rounded()
        if abs(pi.measuredContentHeight - desired) >= 1 {
            pi.measuredContentHeight = desired
        }
    }

    // MARK: Actions

    private func submit() {
        let text = pi.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Sending a prompt always rejoins the streamed tail.
        isFollowingTail = true
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

/// Reports the transcript's top edge within the answer ScrollView's coordinate space
/// (the scroll position probe behind stick-to-bottom).
private struct PiScrollMinYKey: PreferenceKey {
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
