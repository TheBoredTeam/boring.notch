import AppKit
import SwiftUI

public struct CodexReplyComposer: View {
    @Binding private var text: String
    private let chatTitle: String
    private let canSend: Bool
    private let isEditable: Bool
    private let isSending: Bool
    private let acknowledgement: String?
    private let onSend: () -> Void
    private let onDismiss: () -> Void
    private let onFocusChange: (Bool) -> Void
    private let onInteraction: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editorHeight: CGFloat = 14
    @State private var surfaceHeight: CGFloat = 34
    @State private var rollProgress: CGFloat = 0

    private var shouldRetract: Bool { isSending || acknowledgement != nil }

    public init(
        text: Binding<String>, chatTitle: String, canSend: Bool, isEditable: Bool,
        isSending: Bool, acknowledgement: String?, onSend: @escaping () -> Void,
        onDismiss: @escaping () -> Void, onFocusChange: @escaping (Bool) -> Void,
        onInteraction: @escaping () -> Void
    ) {
        _text = text
        self.chatTitle = chatTitle
        self.canSend = canSend
        self.isEditable = isEditable
        self.isSending = isSending
        self.acknowledgement = acknowledgement
        self.onSend = onSend
        self.onDismiss = onDismiss
        self.onFocusChange = onFocusChange
        self.onInteraction = onInteraction
    }

    public var body: some View {
        ZStack(alignment: .trailing) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Reply…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                CodexReplyTextEditor(
                    text: $text, isEditable: isEditable,
                    onSend: onSend, onDismiss: onDismiss,
                    onFocusChange: onFocusChange, onInteraction: onInteraction,
                    onHeightChange: {
                        editorHeight = $0
                        if !shouldRetract { surfaceHeight = max(34, $0 + 16) }
                    }
                )
                .frame(height: editorHeight)
            }
            .padding(.leading, 12)
            .padding(.trailing, 42)
            .frame(maxWidth: .infinity, minHeight: surfaceHeight, maxHeight: surfaceHeight)
            .modifier(CodexReplyFieldMotion(progress: rollProgress, reduceMotion: reduceMotion))
            .allowsHitTesting(isEditable && !shouldRetract)
            .accessibilityHidden(shouldRetract)

            sendGlyph
            .foregroundStyle(canSend || shouldRetract ? Color.white : Color.white.opacity(0.35))
            .help("Send reply (Return). Shift-Return adds a line.")
            .accessibilityLabel("Send reply to \(chatTitle)")
            .accessibilityHidden(shouldRetract)
            .modifier(CodexReplyGlyphMotion(progress: rollProgress, isDelivery: false, reduceMotion: reduceMotion))
            .padding(.trailing, 10)

            if shouldRetract {
                deliveryGlyph
                    .frame(width: 18, height: 18)
                    .animation(.easeOut(duration: 0.18), value: acknowledgement)
                    .modifier(CodexReplyGlyphMotion(progress: rollProgress, isDelivery: true, reduceMotion: reduceMotion))
                    .padding(.trailing, 10)
            }
        }
        .frame(height: surfaceHeight)
        .onAppear {
            // Reopening shows current delivery without replaying the submission.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { rollProgress = shouldRetract ? 1 : 0 }
        }
        .onChange(of: shouldRetract) { _, retract in
            if !retract { surfaceHeight = max(34, editorHeight + 16) }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15)
                          : .timingCurve(0.42, 0, 0.23, 1, duration: retract ? 0.6 : 0.38)) {
                rollProgress = retract ? 1 : 0
            }
        }
    }

    @ViewBuilder
    private var sendGlyph: some View {
        if shouldRetract {
            // A disabled native button dims abruptly; keep the outgoing glyph white.
            arrow
        } else {
            Button(action: onSend) { arrow.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .disabled(!canSend)
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 18, height: 18)
    }

    @ViewBuilder
    private var deliveryGlyph: some View {
        if let acknowledgement {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
                .help(acknowledgement)
                .accessibilityLabel(acknowledgement)
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.94)))
        } else {
            Group {
                if reduceMotion {
                    Image(systemName: "circle.dotted").font(.system(size: 14))
                } else {
                    CodexReplyLoadingRing()
                }
            }
            .accessibilityLabel("Sending reply")
            .transition(.opacity)
        }
    }
}

/// Geometry and opacity share the same interpolated progress on every frame.
private struct CodexReplyFieldMotion: AnimatableModifier {
    var progress: CGFloat
    let reduceMotion: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let outline = CodexReplyRetraction(progress: reduceMotion ? 0 : progress)
        let surfaceOpacity = reduceMotion ? 1 - progress : 1 - replyMotionPhase(progress, 0.68, 1)
        content
            .opacity(1 - replyMotionPhase(progress, 0, reduceMotion ? 1 : 0.4))
            .mask(outline)
            .background(outline.fill(Color.white.opacity(0.04)).opacity(surfaceOpacity))
            .overlay(outline.stroke(Color.white.opacity(0.2), lineWidth: 1).opacity(surfaceOpacity))
    }
}

private struct CodexReplyGlyphMotion: AnimatableModifier {
    var progress: CGFloat
    let isDelivery: Bool
    let reduceMotion: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let visibility = reduceMotion ? progress : replyMotionPhase(progress, isDelivery ? 0.65 : 0.55, isDelivery ? 1 : 0.93)
        content.opacity(isDelivery ? visibility : 1 - visibility)
    }
}

private func replyMotionPhase(_ progress: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
    let value = min(1, max(0, (progress - start) / (end - start)))
    return value * value * (3 - 2 * value)
}

private struct CodexReplyLoadingRing: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.88)
            .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            .frame(width: 13, height: 13)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { spinning = true }
            }
            .onDisappear { spinning = false }
    }
}

/// A pill contracts into the fixed send position; the card's layout stays still.
private struct CodexReplyRetraction: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = min(1, max(0, progress))
        let height = rect.height + (34 - rect.height) * progress
        let left = max(0, rect.width - 36) * progress
        let bounds = CGRect(x: rect.minX + left, y: rect.midY - height / 2,
                            width: rect.width - left - 2 * progress, height: height)
        return RoundedRectangle(cornerRadius: 17, style: .continuous).path(in: bounds.insetBy(dx: 0.5, dy: 0.5))
    }
}

/// AppKit supplies editing, selection, paste, IME and a three-line scroll viewport.
struct CodexReplyTextEditor: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let onSend: () -> Void
    let onDismiss: () -> Void
    let onFocusChange: (Bool) -> Void
    let onInteraction: () -> Void
    let onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        let editor = Editor()
        editor.font = .systemFont(ofSize: 11)
        editor.textColor = .white
        editor.insertionPointColor = .white
        editor.drawsBackground = false
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 14)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel("Reply to this Codex conversation")
        editor.setAccessibilityHelp("Return sends. Shift-Return adds a line. Escape collapses and keeps the draft.")
        editor.onLayout = { [weak coordinator = context.coordinator] in coordinator?.measure() }
        scroll.documentView = editor
        context.coordinator.editor = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? Editor else { return }
        editor.onSend = onSend
        editor.onDismiss = onDismiss
        editor.onFocusChange = onFocusChange
        editor.onInteraction = onInteraction
        editor.isEditable = isEditable
        // Never replace marked text while an input method is composing.
        if !editor.hasMarkedText(), editor.string != text { editor.string = text }
        context.coordinator.measure()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodexReplyTextEditor
        weak var editor: Editor?
        private var measuredHeight: CGFloat = 14
        init(_ parent: CodexReplyTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            parent.text = editor.string
            parent.onInteraction()
            measure()
        }

        func measure() {
            guard let editor, editor.bounds.width > 40,
                  let layout = editor.layoutManager, let container = editor.textContainer else { return }
            layout.ensureLayout(for: container)
            let height = min(42, max(14, ceil(layout.usedRect(for: container).height)))
            guard height != measuredHeight else { return }
            measuredHeight = height
            DispatchQueue.main.async { [weak self] in self?.parent.onHeightChange(height) }
        }
    }

    final class Editor: NSTextView {
        var onSend: () -> Void = {}
        var onDismiss: () -> Void = {}
        var onFocusChange: (Bool) -> Void = { _ in }
        var onInteraction: () -> Void = {}
        var onLayout: () -> Void = {}

        override func layout() { super.layout(); onLayout() }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.makeKey()
            super.mouseDown(with: event)
        }
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { onFocusChange(true) }
            return accepted
        }
        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            if accepted { onFocusChange(false) }
            return accepted
        }
        override func keyDown(with event: NSEvent) {
            onInteraction()
            if !hasMarkedText() {
                if (event.keyCode == 36 || event.keyCode == 76), !event.modifierFlags.contains(.shift) {
                    if isEditable { onSend() }
                    return
                }
                if event.keyCode == 53 { onDismiss(); return }
            }
            super.keyDown(with: event)
        }
    }
}
