import AppKit
import SwiftUI

private enum WindowsTabTheme {
    static let etchedBorder = Color.white.opacity(0.20)
    static let etchedBorderLit = Color.white.opacity(0.35)
    static let glyphFillDim = Color.white.opacity(0.45)
    static let glyphFillLit = Color.white
    static let cardActive = Color.white.opacity(0.055)
    static let cardHover = Color.white.opacity(0.025)
    static let chipHover = Color.white.opacity(0.04)
    static let chipActive = Color.white.opacity(0.07)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.42)
    static let posLabel = Color.white.opacity(0.70)
    static let errorTint = Color.red.opacity(0.78)
    static let monitorBorder = Color.white.opacity(0.10)
    static let appIconBackground = Color.white.opacity(0.04)
}

/// Three-column Windows tab: stage strip of on-screen apps, live preview monitor, identity + snap chips.
struct WindowPowerView: View {
    @EnvironmentObject var vm: GojoViewModel
    @State private var hoverPreview: WindowAction?

    var body: some View {
        WindowsTabPanel(
            state: vm.windowPowerState,
            screenUUID: vm.screenUUID,
            hoverPreview: $hoverPreview
        )
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: vm.screenUUID) {
            await refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWorkspace.didActivateApplicationNotification)
        ) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        await WindowActionExecutor.shared.refreshFocusedWindow(
            screenUUID: vm.screenUUID,
            state: vm.windowPowerState,
            promptIfNeeded: false
        )
    }
}

// MARK: - Panel

private struct WindowsTabPanel: View {
    @ObservedObject var state: WindowPowerState
    let screenUUID: String?
    @Binding var hoverPreview: WindowAction?

    var body: some View {
        HStack(spacing: 0) {
            StageStrip(
                windows: state.windows,
                focusedID: targetSummary?.id,
                onSelect: { summary in
                    state.focusedWindowID = summary.id
                    Task {
                        _ = await XPCHelperClient.shared.raiseWindow(
                            pid: summary.pid,
                            windowID: summary.windowID
                        )
                        NSRunningApplication(processIdentifier: summary.pid)?.activate(options: [])
                    }
                }
            )
            .frame(width: 72)

            PreviewMonitor(action: effectiveAction)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 10)

            RightColumn(
                state: state,
                target: targetSummary,
                hoverPreview: $hoverPreview,
                onAction: execute
            )
            .frame(width: 232)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The window the right column + chip actions act on:
    /// explicitly selected stage card, otherwise the topmost enumerated window.
    private var targetSummary: WindowSummary? {
        if let id = state.focusedWindowID,
           let match = state.windows.first(where: { $0.id == id }) {
            return match
        }
        return state.windows.first
    }

    private var effectiveAction: WindowAction? {
        if let hoverPreview { return hoverPreview }
        return targetSummary?.currentAction ?? state.lastAction
    }

    private func execute(_ action: WindowAction) {
        let target = targetSummary
        Task {
            await WindowActionExecutor.shared.execute(
                action,
                target: target,
                screenUUID: screenUUID,
                state: state
            )
        }
    }
}

// MARK: - Stage strip

private struct StageStrip: View {
    let windows: [WindowSummary]
    let focusedID: String?
    let onSelect: (WindowSummary) -> Void

    private let cardHeight: CGFloat = 32

    var body: some View {
        if windows.isEmpty {
            EmptyStagePlaceholder()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(windows) { window in
                        StageCard(
                            summary: window,
                            isFocused: window.id == focusedID,
                            onSelect: { onSelect(window) }
                        )
                        .frame(height: cardHeight)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            .frame(maxHeight: .infinity)
        }
    }
}

private struct StageCard: View {
    let summary: WindowSummary
    let isFocused: Bool
    let onSelect: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                AppIconView(icon: summary.icon, fallbackName: summary.appName)
                    .frame(width: 22, height: 22)
                    .opacity(isFocused || isHovering ? 1 : 0.78)

                Spacer(minLength: 0)

                WindowPositionGlyph(action: summary.currentAction, isLit: isFocused || isHovering)
                    .frame(width: 18, height: 12)
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isFocused ? WindowsTabTheme.cardActive : (isHovering ? WindowsTabTheme.cardHover : .clear))
                    if isFocused {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2)
                            .padding(.vertical, 6)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityLabel(summary.appName)
        .accessibilityHint("Highlight \(summary.appName) and bring it forward")
    }
}

private struct EmptyStagePlaceholder: View {
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "macwindow")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(WindowsTabTheme.tertiaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AppIconView: View {
    let icon: NSImage?
    let fallbackName: String

    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(WindowsTabTheme.appIconBackground)
                .overlay(
                    Text(monogram)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))
                )
        }
    }

    private var monogram: String {
        String(fallbackName.prefix(1)).uppercased()
    }
}

// MARK: - Preview monitor

private struct PreviewMonitor: View {
    let action: WindowAction?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Hatched screen surface
                Color.clear
                    .background(
                        Canvas { ctx, size in
                            let step: CGFloat = 12
                            let lineColor = Color.white.opacity(0.022)
                            let diag = size.width + size.height
                            var x = -size.height
                            while x < diag {
                                var path = Path()
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                                ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
                                x += step
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(WindowsTabTheme.monitorBorder, lineWidth: 1)
                    )

                if let action {
                    PreviewWindowRect(action: action, in: proxy.size)
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.32), value: action)
        }
    }
}

private struct PreviewWindowRect: View {
    let action: WindowAction
    let containerSize: CGSize

    init(action: WindowAction, in containerSize: CGSize) {
        self.action = action
        self.containerSize = containerSize
    }

    var body: some View {
        let rect = Self.rect(for: action, in: containerSize)
        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                // Traffic-light dots
                HStack(spacing: 2.5) {
                    Circle().fill(Color.white.opacity(0.55)).frame(width: 3, height: 3)
                    Circle().fill(Color.white.opacity(0.55)).frame(width: 3, height: 3)
                    Circle().fill(Color.white.opacity(0.55)).frame(width: 3, height: 3)
                }
                .padding(.leading, 4)
                .padding(.top, 3)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    static func rect(for action: WindowAction, in size: CGSize) -> CGRect {
        let inset: CGFloat = 4
        let innerW = size.width - inset * 2
        let innerH = size.height - inset * 2
        let halfW = innerW / 2 - 1
        let halfH = innerH / 2 - 1
        switch action {
        case .leftHalf:
            return CGRect(x: inset, y: inset, width: halfW, height: innerH)
        case .rightHalf:
            return CGRect(x: size.width - inset - halfW, y: inset, width: halfW, height: innerH)
        case .topHalf:
            return CGRect(x: inset, y: inset, width: innerW, height: halfH)
        case .bottomHalf:
            return CGRect(x: inset, y: size.height - inset - halfH, width: innerW, height: halfH)
        case .maximize:
            return CGRect(x: inset, y: inset, width: innerW, height: innerH)
        }
    }
}

// MARK: - Right column (identity + chips)

private struct RightColumn: View {
    @ObservedObject var state: WindowPowerState
    let target: WindowSummary?
    @Binding var hoverPreview: WindowAction?
    let onAction: (WindowAction) -> Void

    var body: some View {
        VStack(spacing: 8) {
            IdentityRow(state: state, target: target)
            ChipGrid(
                currentAction: target?.currentAction ?? state.lastAction,
                hoverPreview: $hoverPreview,
                onAction: onAction
            )
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct IdentityRow: View {
    @ObservedObject var state: WindowPowerState
    let target: WindowSummary?

    var body: some View {
        HStack(spacing: 9) {
            AppIconView(
                icon: target?.icon,
                fallbackName: displayName
            )
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    Text(positionReadout)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(WindowsTabTheme.posLabel)
                        .lineLimit(1)
                    if let detail = secondaryDetail {
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.25))
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.leading, 2)
    }

    private var displayName: String {
        if let target { return target.appName }
        if let appName = state.appName { return appName }
        if state.statusKind == .error { return state.title }
        return "No window"
    }

    private var positionReadout: String {
        if let action = target?.currentAction ?? state.lastAction {
            return action.label.uppercased()
        }
        switch state.statusKind {
        case .error: return "UNAVAILABLE"
        case .warning: return target == nil ? "NO WINDOW" : "FREE"
        default: return "FREE"
        }
    }

    private var secondaryDetail: String? {
        if let title = target?.title, !title.isEmpty { return title }
        if let title = state.windowTitle, !title.isEmpty { return title }
        if state.statusKind == .error { return state.detail.isEmpty ? nil : state.detail }
        return nil
    }
}

private struct ChipGrid: View {
    let currentAction: WindowAction?
    @Binding var hoverPreview: WindowAction?
    let onAction: (WindowAction) -> Void

    // Five WindowActions plus one empty slot, arranged 3×2.
    private let cells: [WindowAction?] = [
        .leftHalf, .topHalf, .maximize,
        .rightHalf, .bottomHalf, nil
    ]

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(cells.indices, id: \.self) { idx in
                if let action = cells[idx] {
                    Chip(
                        action: action,
                        isOn: currentAction == action,
                        hoverPreview: $hoverPreview,
                        onAction: onAction
                    )
                } else {
                    Color.clear
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct Chip: View {
    let action: WindowAction
    let isOn: Bool
    @Binding var hoverPreview: WindowAction?
    let onAction: (WindowAction) -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            onAction(action)
        } label: {
            WindowPositionGlyph(action: action, isLit: isOn || isHovering)
                .frame(width: 28, height: 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            hoverPreview = hovering ? action : nil
        }
        .accessibilityLabel(action.label)
    }

    private var background: Color {
        if isOn { return WindowsTabTheme.chipActive }
        if isHovering { return WindowsTabTheme.chipHover }
        return .clear
    }
}

// MARK: - Position glyph (signature)

/// Screen-shaped rectangle with the occupied region filled. Used in the stage strip and on chips.
private struct WindowPositionGlyph: View {
    let action: WindowAction?
    let isLit: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let pad: CGFloat = 2

            ZStack {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .strokeBorder(
                        isLit ? WindowsTabTheme.etchedBorderLit : WindowsTabTheme.etchedBorder,
                        lineWidth: 1
                    )

                if let rect = Self.filledRect(for: action, w: w, h: h, pad: pad) {
                    RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                        .fill(isLit ? WindowsTabTheme.glyphFillLit : WindowsTabTheme.glyphFillDim)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .animation(.smooth(duration: 0.28), value: action)
        }
    }

    static func filledRect(for action: WindowAction?, w: CGFloat, h: CGFloat, pad: CGFloat) -> CGRect? {
        guard let action else { return nil }
        let innerW = max(0, w - pad * 2)
        let innerH = max(0, h - pad * 2)
        let halfW = max(0, innerW / 2 - pad / 2)
        let halfH = max(0, innerH / 2 - pad / 2)
        switch action {
        case .leftHalf:
            return CGRect(x: pad, y: pad, width: halfW, height: innerH)
        case .rightHalf:
            return CGRect(x: w - pad - halfW, y: pad, width: halfW, height: innerH)
        case .topHalf:
            return CGRect(x: pad, y: pad, width: innerW, height: halfH)
        case .bottomHalf:
            return CGRect(x: pad, y: h - pad - halfH, width: innerW, height: halfH)
        case .maximize:
            return CGRect(x: pad, y: pad, width: innerW, height: innerH)
        }
    }
}

#Preview {
    WindowPowerView()
        .environmentObject(GojoViewModel())
        .frame(width: openNotchSize.width, height: openNotchSize.height)
        .background(Color.black)
}
