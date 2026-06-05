//
//  ComposioMenuBarView.swift
//  boringNotch
//
//  The native-glass Composio connections app: a second `MenuBarExtra` (`.window` style)
//  that observes `ComposioConnectionManager.shared`. Shows connected accounts grouped by
//  toolkit with traffic-light status dots, lets the user pick a default account per
//  toolkit (★), reconnect expired accounts, and connect a new app — all out of band
//  through the sidecar, never through the agent's chat (so it can't reintroduce the
//  removed deeplink-in-transcript bug).
//
//  No aurora here — that lives only in the hover-expanded notch (PiAgentView). This
//  surface is quiet, native glass per the surfaces-split-by-frequency decision.
//

import AppKit
import Defaults
import SwiftUI

struct ComposioMenuBarView: View {
    @ObservedObject private var conn = ComposioConnectionManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias Connection = ComposioConnectionManager.Connection
    private typealias ConnectionNeed = ComposioConnectionManager.ConnectionNeed
    private typealias StatusTier = ComposioConnectionManager.StatusTier

    /// Connect-an-app inline form state.
    @State private var showConnectField = false
    @State private var connectSlug = ""
    @State private var connectAlias = ""
    /// Drives the light entrance stagger; reset on disappear so re-open re-staggers.
    @State private var appeared = false
    @FocusState private var slugFocused: Bool

    /// The account row currently under the cursor — drives the native-style row
    /// highlight and brings that row's quiet inline actions forward.
    @State private var hoveredRow: String?
    /// One-shot rotation counter: each refresh tap spins the glyph a full turn so the
    /// (otherwise invisible) reconcile has a tactile acknowledgement.
    @State private var refreshSpins = 0

    /// Inline alias-rename state: the account id whose row is in edit mode, plus its draft.
    @State private var renamingId: String?
    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool

    /// User-resizable popover dimensions, persisted across opens/launches (drag the grip).
    @Default(.composioMenubarWidth) private var menuWidth
    @Default(.composioMenubarContentHeight) private var contentHeight
    /// Baselines captured at drag start so the resize tracks the cursor 1:1.
    @State private var dragStartWidth: CGFloat?
    @State private var dragStartHeight: CGFloat?

    private static let widthRange: ClosedRange<CGFloat> = 280...560
    private static let heightRange: ClosedRange<CGFloat> = 140...680

    private var connectedCount: Int {
        conn.connections.values.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)
            content
                .frame(height: contentHeight) // the resizable scrollable region
            Divider().opacity(0.4)
            connectFooter
        }
        .frame(width: menuWidth)
        // Native glass: on macOS 26 the `.window` MenuBarExtra is already Liquid Glass;
        // this guarantees the popover material on the macOS 14 deployment floor too.
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        // Bottom-trailing grip — drag to resize; the size persists across opens/launches.
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        .onAppear {
            conn.refresh() // reconcile list + file-sourced defaults each time it opens
            withAnimation(reduceMotion ? Motion.reduced : Motion.hover) { appeared = true }
        }
        .onDisappear { appeared = false }
    }

    /// A diagonal corner grip. Dragging adjusts width + the scrollable height, clamped to
    /// sane ranges, writing straight to `@Default` so the preference sticks.
    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary.opacity(0.7))
            // The glyph already runs along the ↖︎↘︎ axis — exactly the resize axis of a
            // bottom-trailing grip. (It was previously rotated 90°, which pointed it the
            // wrong way, along ↗︎↙︎.)
            .padding(5)
            .contentShape(Rectangle())
            .gesture(
                // Measure the drag in GLOBAL space, not the grip's local space. The grip is
                // overlaid at the panel's bottom-trailing corner, so as the panel grows the
                // grip moves with it — in local space that inflates `translation` even when
                // the cursor is still, a feedback loop that made resizing jump and run away.
                // The popover window's origin is pinned to the menu bar (it only grows down/
                // right), so global coordinates are stable and the delta tracks the cursor 1:1.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let w0 = dragStartWidth ?? menuWidth
                        let h0 = dragStartHeight ?? contentHeight
                        if dragStartWidth == nil {
                            dragStartWidth = w0
                            dragStartHeight = h0
                        }
                        menuWidth = min(max(w0 + value.translation.width, Self.widthRange.lowerBound), Self.widthRange.upperBound)
                        contentHeight = min(max(h0 + value.translation.height, Self.heightRange.lowerBound), Self.heightRange.upperBound)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        dragStartHeight = nil
                    }
            )
            .onHover { inside in
                if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            .help("Drag to resize")
            .accessibilityLabel("Resize panel")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Composio")
                    .font(.system(size: 13, weight: .semibold))
                Text(connectedCount == 1 ? "1 account connected" : "\(connectedCount) accounts connected")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                conn.refresh()
                // One full turn on the ease-out-quint curve — an exit-flavored flick that
                // confirms the tap. Skipped under Reduce Motion (the data still refreshes).
                if !reduceMotion {
                    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.55)) { refreshSpins += 1 }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(Double(refreshSpins) * 360))
            }
            .buttonStyle(PressStyle(reduceMotion: reduceMotion))
            .help("Refresh")
            .accessibilityLabel("Refresh connections")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: Content (grouped accounts)

    @ViewBuilder
    private var content: some View {
        if conn.toolkits.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(conn.toolkits.enumerated()), id: \.element) { index, toolkit in
                        toolkitGroup(toolkit)
                            // Light entrance: fade + 4pt rise, staggered ~40ms per group.
                            // No idle motion — this only plays once on open.
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 4)
                            .animation(rowAnimation(index), value: appeared)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func rowAnimation(_ index: Int) -> Animation {
        if reduceMotion { return Motion.reduced }
        return Motion.hover.delay(Double(min(index, 6)) * 0.04)
    }

    private func toolkitGroup(_ toolkit: String) -> some View {
        let accounts = conn.connections[toolkit] ?? []
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                toolkitLogo(toolkit)
                Text(toolkit.capitalized)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            ForEach(accounts) { account in
                accountRow(toolkit: toolkit, account: account)
            }
        }
    }

    @ViewBuilder
    private func accountRow(toolkit: String, account: Connection) -> some View {
        // Identity in the user's preferred order: alias → wordId → account id. The agent
        // resolver matches any of the three, so this same value is the default selector.
        let selector = account.selector
        let isDefault = conn.defaultAliases[toolkit.lowercased()] == selector
        let isHovered = hoveredRow == account.connectedAccountId
        HStack(spacing: 8) {
            statusDot(account.statusTier)
            if renamingId == account.connectedAccountId {
                renameField(toolkit: toolkit, account: account)
            } else {
                Text(account.displayName)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if account.needsReauth {
                    Button("Reconnect") {
                        conn.reconnect(
                            ConnectionNeed(
                                toolkit: toolkit,
                                alias: account.alias,
                                connectedAccountId: account.connectedAccountId,
                                status: account.status
                            )
                        )
                    }
                    .buttonStyle(PressStyle(reduceMotion: reduceMotion))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.effectiveAccent)
                    .help("Reopen the hosted auth page for this account")
                }
                // Inline actions — no hidden menu, every action one click away: rename/
                // clear the alias, star the default account, or disconnect. Quiet at rest
                // so a column of them doesn't shout; they brighten as the row is hovered.
                HStack(spacing: 3) {
                    RowIconButton(
                        systemName: "pencil",
                        help: account.alias == nil ? "Set an alias (e.g. work)" : "Rename alias",
                        reduceMotion: reduceMotion,
                        rowHovered: isHovered
                    ) { startRename(account) }
                    starButton(toolkit: toolkit, selector: selector, isDefault: isDefault, rowHovered: isHovered)
                    RowIconButton(
                        systemName: "trash",
                        help: "Disconnect this account",
                        destructive: true,
                        reduceMotion: reduceMotion,
                        rowHovered: isHovered
                    ) {
                        if renamingId == account.connectedAccountId { cancelRename() }
                        conn.deleteConnection(account, toolkit: toolkit)
                    }
                }
            }
        }
        .padding(.leading, 2)
        .padding(.vertical, 3)
        // Native-style row highlight. The shape is inset out into the group's gutter via
        // negative padding so the fill reads as a full-width row without altering layout.
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
                .padding(.horizontal, -8)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            let id = account.connectedAccountId
            if hovering { hoveredRow = id }
            else if hoveredRow == id { hoveredRow = nil }
        }
        .animation(reduceMotion ? Motion.reduced : .easeOut(duration: 0.13), value: isHovered)
    }

    /// Inline alias editor: replaces the name + trailing controls while a row is renaming.
    /// ↵ or Save commits; an empty value clears the alias (falls back to the word id).
    @ViewBuilder
    private func renameField(toolkit: String, account: Connection) -> some View {
        TextField("Alias (e.g. work)", text: $renameDraft)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .focused($renameFocused)
            .frame(maxWidth: 150)
            .onSubmit { commitRename(account: account, toolkit: toolkit) }
            .onExitCommand(perform: cancelRename)
        Spacer(minLength: 4)
        // Clear → remove the alias entirely (only when one exists). One tap to "delete
        // alias"; the row falls back to the Composio word id.
        if account.alias != nil {
            Button("Clear") {
                conn.renameConnection(account, toolkit: toolkit, alias: "")
                cancelRename()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Remove this alias")
        }
        Button("Save") { commitRename(account: account, toolkit: toolkit) }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
        Button("Cancel") { cancelRename() }
            .buttonStyle(.bordered)
            .controlSize(.mini)
    }

    private func startRename(_ account: Connection) {
        renameDraft = account.alias ?? ""
        withAnimation(reduceMotion ? Motion.reduced : Motion.hover) {
            renamingId = account.connectedAccountId
        }
        renameFocused = true
    }

    private func commitRename(account: Connection, toolkit: String) {
        conn.renameConnection(account, toolkit: toolkit, alias: renameDraft)
        cancelRename()
    }

    private func cancelRename() {
        withAnimation(reduceMotion ? Motion.reduced : Motion.hover) { renamingId = nil }
        renameDraft = ""
        renameFocused = false
    }

    private func statusDot(_ tier: StatusTier) -> some View {
        let tint = color(for: tier)
        return Circle()
            .fill(tint)
            .frame(width: 8, height: 8)
            // A faint same-color bloom behind the dot — reads as a lit indicator rather
            // than a flat sticker, and survives both light and dark popover glass.
            .background(
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .blur(radius: 2.5)
                    .opacity(0.55)
            )
            // Inner light ring + outer dark ring: definition on any background, where a
            // single black ring vanished against the dark popover.
            .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5).blendMode(.plusLighter))
            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            // Color crossfade when an account changes health (green→red→green); no movement.
            .animation(reduceMotion ? Motion.reduced : Motion.flash, value: tier)
            .accessibilityLabel(accessibilityLabel(for: tier))
    }

    private func color(for tier: StatusTier) -> Color {
        switch tier {
        case .active: return .green
        case .pending: return .yellow
        case .attention: return .red
        }
    }

    private func accessibilityLabel(for tier: StatusTier) -> String {
        switch tier {
        case .active: return "Active"
        case .pending: return "Connecting"
        case .attention: return "Needs attention"
        }
    }

    private func starButton(toolkit: String, selector: String, isDefault: Bool, rowHovered: Bool = false) -> some View {
        Button {
            // One default per group: starring a row clears any other; un-starring → Automatic.
            conn.setDefaultAlias(isDefault ? nil : selector, for: toolkit)
        } label: {
            Image(systemName: isDefault ? "star.fill" : "star")
                .font(.system(size: 11))
                // A set default stays gold; an unset star is quiet at rest and lifts toward
                // primary as the row is hovered, hinting it's actionable.
                .foregroundStyle(isDefault ? Color.yellow : Color.secondary.opacity(rowHovered ? 0.85 : 0.45))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressStyle(reduceMotion: reduceMotion))
        .help(isDefault
              ? "Default account for \(toolkit.capitalized) — click to use Automatic"
              : "Make this the default account for \(toolkit.capitalized)")
        .accessibilityLabel(isDefault ? "Default account" : "Set as default account")
    }

    private func toolkitLogo(_ slug: String) -> some View {
        // Prefer the logo resolved from Composio toolkit metadata (meta.logo); fall back
        // to the logo CDN by slug. `ToolkitLogoView` loads through NSImage (not AsyncImage)
        // so Composio's SVG marks decode reliably, and sits the mark on a light plate so
        // solid-black brands (GitHub, Notion, X…) stay legible against the dark popover.
        ToolkitLogoView(urlString: conn.toolkitLogos[slug] ?? "https://logos.composio.dev/api/\(slug)")
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.effectiveAccent.opacity(0.10))
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.effectiveAccent.opacity(0.18), lineWidth: 0.75)
                    )
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.effectiveAccent)
            }
            VStack(spacing: 4) {
                Text("No connected apps yet")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Connect an app below, or sign in with the `composio` CLI. Gmail, Calendar, Notion and more will show up here.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    // MARK: Connect an app (out of band — never through the agent)

    @ViewBuilder
    private var connectFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showConnectField {
                connectForm
                    .transition(Motion.transition(Motion.overlay, reduceMotion: reduceMotion))
            } else {
                Button {
                    withAnimation(reduceMotion ? Motion.reduced : Motion.hover) { showConnectField = true }
                    slugFocused = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("Connect an app…")
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(reduceMotion: reduceMotion))
                .foregroundStyle(Color.effectiveAccent)
                .transition(Motion.transition(.opacity, reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .animation(reduceMotion ? Motion.reduced : Motion.hover, value: showConnectField)
    }

    private var connectForm: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField("Toolkit slug (e.g. gmail, notion)", text: $connectSlug)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
                .focused($slugFocused)
                .onSubmit(submitConnect)
                .onExitCommand(perform: cancelConnect)
            TextField("Alias (optional, e.g. work)", text: $connectAlias)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
                .onSubmit(submitConnect)
            HStack(spacing: 8) {
                Text("Opens the hosted auth page in your browser.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { cancelConnect() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Connect") { submitConnect() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(connectSlug.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func submitConnect() {
        let slug = connectSlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !slug.isEmpty else { return }
        let alias = connectAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        conn.connect(toolkit: slug, alias: alias.isEmpty ? nil : alias)
        cancelConnect()
    }

    private func cancelConnect() {
        withAnimation(reduceMotion ? Motion.reduced : Motion.hover) { showConnectField = false }
        connectSlug = ""
        connectAlias = ""
        slugFocused = false
    }
}

/// A compact, always-visible row action (rename / disconnect). Subtle at rest so a row
/// of them doesn't shout, brightening on hover; the destructive variant goes red on hover
/// so disconnect reads as dangerous without a confirmation modal getting in the way.
private struct RowIconButton: View {
    let systemName: String
    let help: String
    var destructive: Bool = false
    let reduceMotion: Bool
    /// Whether the parent account row is hovered. Lifts the icon out of its quiet rest
    /// tint so a column of actions stays calm until you're actually on that row.
    var rowHovered: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(reduceMotion: reduceMotion))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? Motion.reduced : .easeOut(duration: 0.13), value: hovering)
        .animation(reduceMotion ? Motion.reduced : .easeOut(duration: 0.13), value: rowHovered)
        .help(help)
        .accessibilityLabel(help)
    }

    private var tint: Color {
        // Direct hover wins (red arms a destructive action); otherwise the row-hover
        // state decides between "present" and the calm rest tint.
        if hovering { return destructive ? .red : Color.primary.opacity(0.9) }
        let resting = rowHovered ? 0.85 : 0.45
        return Color.secondary.opacity(resting)
    }
}

/// A toolkit brand mark on a light plate. Loads through `NSImage(data:)` rather than
/// `AsyncImage` because the Composio logo CDN serves SVG, which the notch already decodes
/// this way (PiAgentManager) — AsyncImage's SVG support is inconsistent on the macOS 14
/// floor. The plate matters because many marks are solid black (GitHub, Notion, X…) and
/// would vanish against the dark popover; a near-white backing keeps every brand legible,
/// the same treatment app launchers use for monochrome brand icons.
private struct ToolkitLogoView: View {
    let urlString: String
    @State private var image: NSImage?

    /// Process-wide so re-opening the popover (or a list reconcile) paints instantly
    /// instead of refetching every brand mark.
    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(2.5)
        .frame(width: 20, height: 20)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.95))
        )
        // A hairline edge so the plate doesn't melt into a light popover background, and a
        // whisper of shadow for the same lifted feel app launchers give monochrome marks.
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
        // Fade the mark in once it decodes instead of snapping from the placeholder.
        .animation(.easeOut(duration: 0.18), value: image != nil)
        .task(id: urlString) { await load() }
    }

    private func load() async {
        if let cached = Self.cache.object(forKey: urlString as NSString) {
            image = cached
            return
        }
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let loaded = NSImage(data: data) else { return }
        Self.cache.setObject(loaded, forKey: urlString as NSString)
        image = loaded
    }
}
