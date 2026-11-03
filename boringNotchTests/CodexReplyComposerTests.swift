import AppKit
import SwiftUI
import XCTest
@testable import CodexResponseRendering

@MainActor
final class CodexReplyComposerTests: XCTestCase {
    func testNativeEditorAcceptsTypingNewlinesAndSendWithoutTakingFocusOnHover() throws {
        try withComposer { model, host, window, editor in
            XCTAssertFalse(window.firstResponder === editor, "Showing a preview must not focus its composer")
            window.makeKey()
            XCTAssertTrue(window.makeFirstResponder(editor))
            editor.insertText("A synthetic reply", replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual(model.text, "A synthetic reply")
            XCTAssertGreaterThan(model.interactions, 0, "Native editing must renew the inactivity timer")
            editor.keyDown(with: key(36, characters: "\r", modifiers: [.shift]))
            XCTAssertTrue(editor.string.contains("\n"))
            editor.keyDown(with: key(36, characters: "\r"))
            XCTAssertEqual(model.sends, 1)
            editor.keyDown(with: key(53, characters: "\u{1b}"))
            XCTAssertEqual(model.dismissals, 1)
            XCTAssertFalse(model.text.isEmpty, "Escape must preserve the draft")
        }
    }

    func testMarkedTextConfirmationDoesNotSubmit() throws {
        try withComposer { model, _, window, editor in
            window.makeKey()
            window.makeFirstResponder(editor)
            editor.setMarkedText("你好", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertTrue(editor.hasMarkedText())
            editor.keyDown(with: key(36, characters: "\r"))
            XCTAssertEqual(model.sends, 0)
        }
    }

    func testComposerStartsAtOneLineAndCapsMultilineInput() throws {
        try withComposer { model, host, _, editor in
            XCTAssertEqual(editor.font?.pointSize, 11)
            XCTAssertEqual(host.fittingSize.height - 32, 34, accuracy: 1)
            editor.string = String(repeating: "A synthetic line\n", count: 10)
            editor.didChangeText()
            render(host)
            let scroll = try XCTUnwrap(editor.enclosingScrollView)
            XCTAssertLessThanOrEqual(scroll.contentSize.height, 43)
            XCTAssertGreaterThan(editor.frame.height, scroll.contentSize.height)
            XCTAssertEqual(model.text, editor.string)
        }
    }

    func testFullResponseCardKeepsTheComposerInsideItsHeightBudget() throws {
        let model = ComposerModel()
        model.text = "Synthetic reply draft"
        let host = NSHostingView(rootView: ReplyCardFixture(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 310)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -3000, y: -3000))
        window.orderFront(nil)
        defer { window.close() }
        render(host)
        let editor = try XCTUnwrap(descendant(CodexReplyTextEditor.Editor.self, in: host))
        XCTAssertEqual(editor.enclosingScrollView?.contentSize.height ?? 0, 14, accuracy: 1)
        XCTAssertGreaterThan(model.cardHeight, 180)
        XCTAssertLessThanOrEqual(model.cardHeight + 46, 310)
        descendant(NSScrollView.self, in: host)?.flashScrollers()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        try capture(host, to: "/tmp/boring-notch-quick-reply-card.png")
        model.text = ""
        model.acknowledgement = "Reply received by Codex."
        render(host)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
        XCTAssertFalse(editor.isEditable, "The accepted response allows only one reply")
        try capture(host, to: "/tmp/boring-notch-reply-received.png")
        model.acknowledgement = nil
        render(host)
        XCTAssertTrue(editor.isEditable, "A fresh response enables its own composer")
        editor.insertText("Reply to fresh response", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(model.text, "Reply to fresh response")
    }

    func testSendMotionKeepsMultilineHeightAndRestoresTheDraftAfterFailure() throws {
        try withComposer { model, host, _, editor in
            editor.string = "A synthetic first line\nAnd a second line\nOne final line"
            editor.didChangeText()
            render(host)
            let originalHeight = host.fittingSize.height
            let originalText = model.text
            model.isSending = true
            render(host)
            XCTAssertFalse(editor.isEditable)
            XCTAssertEqual(host.fittingSize.height, originalHeight, accuracy: 1)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
            try capture(host, to: "/tmp/boring-notch-reply-loading.png")
            let pixels = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: URL(fileURLWithPath: "/tmp/boring-notch-reply-loading.png"))))
            let hasVisibleRing = stride(from: 0, to: pixels.pixelsWide, by: 2).contains { x in
                stride(from: 0, to: pixels.pixelsHigh, by: 2).contains { y in
                    guard let color = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                    return min(color.redComponent, color.greenComponent, color.blueComponent) > 0.5
                }
            }
            XCTAssertTrue(hasVisibleRing, "Pending delivery must remain visible after the input rolls away")
            model.isSending = false
            render(host)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
            XCTAssertTrue(editor.isEditable)
            XCTAssertEqual(editor.string, originalText, "A failed send must unroll the same draft")
            XCTAssertEqual(host.fittingSize.height, originalHeight, accuracy: 1)
        }
    }

    func testNativeRollKeepsItsHeightAndHasIntermediateFrames() throws {
        try withComposer { model, host, _, editor in
            editor.string = "A synthetic motion sample"
            editor.didChangeText()
            render(host)
            let directory = URL(fileURLWithPath: "/tmp/boring-notch-native-motion-refined", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let started = Date()
            let originalHeight = host.fittingSize.height
            model.isSending = true
            var times: [Double] = []
            var leadingEdges = Set<Int>()
            for frame in 0..<36 {
                RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 60))
                host.layoutSubtreeIfNeeded()
                host.display()
                times.append(Date().timeIntervalSince(started))
                let path = directory.appendingPathComponent(String(format: "%03d.png", frame))
                try capture(host, to: path.path)
                let pixels = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: path)))
                let edge = stride(from: 0, to: pixels.pixelsWide, by: 2).first { x in
                    guard let color = pixels.colorAt(x: x, y: pixels.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) else { return false }
                    return max(color.redComponent, color.greenComponent, color.blueComponent) > 0.025
                }
                if let edge, edge > 50, edge < pixels.pixelsWide - 100 { leadingEdges.insert(edge) }
                XCTAssertEqual(host.fittingSize.height, originalHeight, accuracy: 1)
            }
            XCTAssertGreaterThan(leadingEdges.count, 6, "The native bar must interpolate through visible intermediate positions")
            try JSONSerialization.data(withJSONObject: times).write(to: directory.appendingPathComponent("times.json"))
        }
    }

    func testFastAcknowledgementFinishesTheRollAndKeepsTheAcceptedInputLocked() throws {
        try withComposer { model, host, _, editor in
            editor.string = "A synthetic reply"
            editor.didChangeText()
            render(host)
            let originalHeight = host.fittingSize.height
            model.isSending = true
            render(host)
            model.isSending = false
            model.acknowledgement = "Reply received by Codex."
            model.text = ""
            render(host)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
            XCTAssertFalse(editor.isEditable)
            XCTAssertEqual(host.fittingSize.height, originalHeight, accuracy: 1)
            try capture(host, to: "/tmp/boring-notch-reply-motion-received.png")
            editor.keyDown(with: key(36, characters: "\r"))
            XCTAssertEqual(model.sends, 0, "The accepted prompt must not submit twice")
            model.acknowledgement = nil
            render(host)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
            XCTAssertTrue(editor.isEditable)
            editor.insertText("Fresh reply", replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual(model.text, "Fresh reply")
        }
    }

    private func capture(_ host: NSView, to path: String) throws {
        let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path))
    }

    private func withComposer(_ inspect: (ComposerModel, NSHostingView<ComposerFixture>, NSWindow, CodexReplyTextEditor.Editor) throws -> Void) throws {
        let model = ComposerModel()
        let host = NSHostingView(rootView: ComposerFixture(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -3000, y: -3000))
        window.orderFront(nil)
        defer { window.close() }
        render(host)
        let editor = try XCTUnwrap(descendant(CodexReplyTextEditor.Editor.self, in: host))
        try inspect(model, host, window, editor)
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        (view as? T) ?? view.subviews.compactMap { descendant(type, in: $0) }.first
    }

    private func render(_ host: NSView) {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            host.display()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        }
    }

    private func key(_ keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                        windowNumber: 0, context: nil, characters: characters,
                        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }
}

@MainActor
private final class ComposerModel: ObservableObject {
    @Published var text = ""
    @Published var cardHeight: CGFloat = 264
    @Published var acknowledgement: String?
    @Published var isSending = false
    var sends = 0
    var dismissals = 0
    var interactions = 0
}

private struct ReplyCardFixture: View {
    @ObservedObject var model: ComposerModel
    var body: some View {
        CodexResponseCard(
            source: "### Update ready\n\n" + String(repeating: "This synthetic response checks that wrapped text stays clear of the scrollbar while the reply input and conversation footer remain visible. ", count: 14),
            isTruncated: false, projectName: "Boring Notch", chatTitle: "Quick reply implementation", launchError: nil,
            maximumHeight: 264, onHeightChange: { model.cardHeight = $0 }, onOpenCodex: {},
            composer: AnyView(CodexReplyComposer(
                text: $model.text, chatTitle: "Quick reply implementation", canSend: !model.text.isEmpty,
                isEditable: model.acknowledgement == nil, isSending: false,
                acknowledgement: model.acknowledgement, onSend: {}, onDismiss: {}, onFocusChange: { _ in }, onInteraction: { model.interactions += 1 }
            ))
        )
        .frame(height: model.cardHeight, alignment: .top)
        .padding(.top, 34)
        .padding(.bottom, 12)
        .frame(width: 640, height: 310, alignment: .top)
        .background(.black)
        .preferredColorScheme(.dark)
    }
}

private struct ComposerFixture: View {
    @ObservedObject var model: ComposerModel
    var body: some View {
        CodexReplyComposer(
            text: $model.text, chatTitle: "Synthetic conversation", canSend: !model.text.isEmpty,
            isEditable: !model.isSending && model.acknowledgement == nil,
            isSending: model.isSending, acknowledgement: model.acknowledgement, onSend: { model.sends += 1 },
            onDismiss: { model.dismissals += 1 }, onFocusChange: { _ in }, onInteraction: { model.interactions += 1 }
        )
        .frame(width: 568)
        .padding(16)
        .background(.black)
        .preferredColorScheme(.dark)
    }
}
