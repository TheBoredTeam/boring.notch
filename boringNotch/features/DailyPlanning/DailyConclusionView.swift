import AppKit
import SwiftUI

struct DailyConclusionView: View {
    @ObservedObject var manager: DailyPlanningManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var promptVisible = false
    @State private var folded = false
    @State private var filed = false
    @State private var settled = false
    @State private var dismissed = false

    private var isFiling: Bool { manager.conclusionPhase == .filing }
    private var isBusy: Bool { manager.conclusionPhase == .saving || isFiling }

    var body: some View {
        ZStack(alignment: .top) {
            if isFiling {
                filingAnimation
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button(action: manager.returnToReview) {
                            Image(systemName: "chevron.left")
                        }
                        .help("Back to task review")
                        .accessibilityLabel("Back to task review")
                        .disabled(isBusy || manager.savedConclusionURL != nil)
                        Text("What would you like to remember about today?")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(isBusy ? "Saving…" : "End Review") {
                            manager.saveConclusion(reduceMotion: reduceMotion)
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.12), in: Capsule())
                        .disabled(isBusy)
                    }
                    .buttonStyle(.plain)
                    ZStack(alignment: .topLeading) {
                        if manager.conclusionText.isEmpty {
                            Text("Write in Markdown… A small win, a thought, anything on your mind.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(.top, 4)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        DailyConclusionEditor(
                            text: $manager.conclusionText,
                            isEditable: !isBusy && manager.savedConclusionURL == nil
                        )
                    }
                    .frame(maxHeight: .infinity)
                    if let error = manager.conclusionError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Save error: \(error)")
                    }
                }
                .padding(.top, 12)
                .opacity(promptVisible ? 1 : 0)
            }
        }
        .foregroundStyle(.white)
        .background(.black)
        .clipped()
        .task {
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { promptVisible = true }
        }
        .task(id: isFiling) {
            guard isFiling else { return }
            folded = false
            filed = false
            settled = false
            dismissed = false
            if reduceMotion { folded = true; filed = true; settled = true; return }
            do {
                try await Task.sleep(for: .milliseconds(30))
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.75)) { folded = true }
                try await Task.sleep(for: .milliseconds(900))
                withAnimation(.timingCurve(0.45, 0, 0.6, 1, duration: 0.6)) { filed = true }
                try await Task.sleep(for: .milliseconds(650))
                withAnimation(.easeOut(duration: 0.25)) { settled = true }
                try await Task.sleep(for: .milliseconds(850))
                withAnimation(.timingCurve(0.45, 0, 0.8, 0.4, duration: 0.5)) { dismissed = true }
            } catch { return }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: isFiling)
    }

    private var filingAnimation: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // The back, paper, and front share one coordinate space. The paper
                // keeps its size during insertion and ends entirely behind the front.
                DailyDiaryFolderBack()
                    .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(DailyDiaryFolderBack().stroke(.white.opacity(0.2), lineWidth: 0.5))
                    .frame(width: 108, height: 72)
                    .offset(y: folded ? 46 : 67)
                    .opacity(folded ? 1 : 0)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<4) { index in
                        Capsule()
                            .fill(Color(white: 0.42).opacity(index == 0 ? 0.65 : 0.35))
                            .frame(width: index == 0 ? 28 : (index == 3 ? 42 : 62), height: 2)
                            .padding(.bottom, index == 0 ? 3 : 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.top, 9)
                .frame(width: 88, height: 48)
                .background(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.77)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 5))
                .overlay(alignment: .topTrailing) {
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: 10, y: 10))
                        path.addLine(to: CGPoint(x: 0, y: 10))
                        path.closeSubpath()
                    }
                    .fill(Color(white: 0.65))
                    .frame(width: 10, height: 10)
                }
                .scaleEffect(x: folded ? 1 : max(1, (geometry.size.width - 24) / 88), y: folded ? 1 : 1.5)
                .rotationEffect(.degrees(folded && !filed ? -6 : 0))
                .opacity(folded ? 1 : 0)
                .offset(y: filed ? 71 : (folded ? 4 : 50))

                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(white: 0.41), Color(white: 0.27), Color(white: 0.19)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.35))
                            .frame(height: 1).padding(.horizontal, 6)
                    }
                    .overlay {
                        Capsule().fill(Color(white: 0.09)).frame(width: 18, height: 3)
                    }
                    .frame(width: 112, height: 50)
                    .scaleEffect(x: folded && !settled ? 1.03 : 1, y: folded && !settled ? 0.83 : 1, anchor: .bottom)
                    .offset(y: folded ? 70 : 91)
                    .opacity(folded ? 1 : 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .offset(y: dismissed ? geometry.size.height : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Diary saved")
    }
}

private struct DailyDiaryFolderBack: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 5, y: 0))
        path.addLine(to: CGPoint(x: 34, y: 0))
        path.addLine(to: CGPoint(x: 46, y: 9))
        path.addLine(to: CGPoint(x: rect.maxX - 8, y: 9))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: 17), control: CGPoint(x: rect.maxX, y: 9))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 8))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 8, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 8, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - 8), control: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: 5))
        path.addQuadCurve(to: CGPoint(x: 5, y: 0), control: .zero)
        path.closeSubpath()
        return path
    }
}

/// Native text editing keeps selection, undo, spell-check, and input methods intact.
private struct DailyConclusionEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = ConclusionTextView()
        editor.isRichText = false
        editor.drawsBackground = false
        editor.textColor = .white
        editor.insertionPointColor = .white
        editor.font = .systemFont(ofSize: 13)
        editor.textContainerInset = NSSize(width: 0, height: 4)
        editor.textContainer?.lineFragmentPadding = 0
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.allowsUndo = true
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.setAccessibilityLabel("Daily conclusion, Markdown editor")
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text { editor.string = text }
        editor.isEditable = isEditable
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? ConclusionTextView)?.releaseKeyboardFocus()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DailyConclusionEditor
        init(_ parent: DailyConclusionEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

private final class ConclusionTextView: NSTextView {
    private weak var inputWindow: BoringNotchWindow?

    func releaseKeyboardFocus() {
        guard let inputWindow, inputWindow.keyboardInputOwner === self else { return }
        if inputWindow.firstResponder === self {
            inputWindow.makeFirstResponder(nil)
            inputWindow.resignKey()
        }
        inputWindow.keyboardInputOwner = nil
        self.inputWindow = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { releaseKeyboardFocus() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window, self.isEditable else { return }
            self.inputWindow = window as? BoringNotchWindow
            self.inputWindow?.keyboardInputOwner = self
            window.makeKey()
            window.makeFirstResponder(self)
        }
    }
}
