import AppKit
import MarkdownUI
import SwiftUI
import XCTest
@testable import CodexResponseRendering

final class CodexResponseRenderingTests: XCTestCase {
    func testRendererParsesTablesAndFencedCodeAsStructuredContent() {
        let content = MarkdownContent("""
        # Result

        | Change | Status |
        | --- | --- |
        | café / 你好 | Ready |

        ```swift
        let greeting = "hello"
        ```

        - First
          - Nested
        """)
        let html = content.renderHTML()
        XCTAssertTrue(html.contains("<table>"))
        let parsedTable = MarkdownContent("| Change | Status |\n| --- | --- |\n| café / 你好 | Ready |")
        struct Row { let change: String; let status: String }
        let expectedTable = MarkdownContent {
            TextTable([Row(change: "café / 你好", status: "Ready")]) {
                TextTableColumn(title: "Change", value: \.change)
                TextTableColumn(title: "Status", value: \.status)
            }
        }
        XCTAssertEqual(parsedTable, expectedTable, "The native table must retain separate columns and cells")
        XCTAssertTrue(html.contains("<pre><code"))
        XCTAssertTrue(content.renderPlainText().contains("你好"))
        XCTAssertTrue(content.renderPlainText().contains("Nested"))
    }

    func testIncompleteAndUnsupportedMarkdownPreservesReadableText() {
        for source in ["```swift\nlet partial =", "| Column | Other |\n| --- | --- |\n| partial", "<details>Still readable</details>"] {
            let text = MarkdownContent(source).renderMarkdown()
            XCTAssertFalse(text.isEmpty)
            XCTAssertTrue(text.contains(source.contains("partial") ? "partial" : "Still readable"))
        }
    }

    func testLinksRequireAnOrdinaryExternalDestination() {
        for target in ["https://example.com", "http://example.com", "mailto:example@example.com"] {
            XCTAssertTrue(CodexResponseMarkdown.allowsLink(URL(string: target)!))
        }
        for target in ["file:///tmp/fixture", "javascript:alert(1)", "data:text/html,fixture", "boringnotch://settings", "codex://threads/fixture"] {
            XCTAssertFalse(CodexResponseMarkdown.allowsLink(URL(string: target)!))
        }
    }

    func testInlineImagesNeverLoadRemoteOrLocalContent() async {
        let provider = CodexResponseInlineImageProvider(equations: [:])
        for target in ["https://example.invalid/image.png", "file:///tmp/image.png", "data:image/png;base64,AA==", "boringnotch-math://equation/untrusted"] {
            do {
                _ = try await provider.image(with: URL(string: target)!, label: "Synthetic image")
            } catch {
                XCTFail("Omitted images must return a local placeholder without loading or cancelling sibling math")
            }
        }
    }

    @MainActor
    func testNativeRenderingMeasuresShortRepliesWithoutBlankSpaceAndBoundsWideTables() {
        let short = NSHostingView(rootView: CodexResponseMarkdown(source: "Updated the **Save preferences** label.").frame(width: 578))
        let long = NSHostingView(rootView: CodexResponseMarkdown(source: String(repeating: "A longer paragraph with useful context.\n\n", count: 40)).frame(width: 578))
        let table = NSHostingView(rootView: CodexResponseMarkdown(source: "| Very wide column name | Another very wide column | Third column |\n| --- | --- | --- |\n| A | B | C |").frame(width: 300))
        XCTAssertGreaterThan(short.fittingSize.height, 0)
        XCTAssertLessThan(short.fittingSize.height, 80)
        XCTAssertGreaterThan(long.fittingSize.height, 140)
        XCTAssertEqual(table.fittingSize.width, 300, accuracy: 1)
        XCTAssertGreaterThan(table.fittingSize.height, 0)
    }

    @MainActor
    func testEffectiveResponseTypographyAndSurfaceMatchTheApprovedRefinement() throws {
        let source = "Small response text."
        let response = CodexResponseMarkdown(source: source)
            .frame(width: 240, alignment: .leading)
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: response)
        let reference = NSHostingView(rootView: Text(source).font(.system(size: 11)).frame(width: 240))
        XCTAssertEqual(host.fittingSize.height, reference.fittingSize.height, accuracy: 1,
                       "The Markdown theme must not restore its larger default font")

        let pixels = try XCTUnwrap(ImageRenderer(content: response).cgImage)
        var buffer = [UInt8](repeating: 0, count: pixels.width * pixels.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &buffer, width: pixels.width, height: pixels.height, bitsPerComponent: 8,
            bytesPerRow: pixels.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(pixels, in: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
        let blankPixelAlpha = ((pixels.height / 2) * pixels.width + pixels.width - 1) * 4 + 3
        XCTAssertEqual(buffer[blankPixelAlpha], 0, "The reply must let the black notch show through")
    }

    @MainActor
    func testCompleteShortCardResizesItsParentWithoutClippingIntoCameraClearance() throws {
        try withHostedCard(source: "The synthetic update is ready.") { model, host in
            XCTAssertTrue(model.reportedHeights.allSatisfy { $0 > 0 })
            XCTAssertFalse(model.reportedHeights.isEmpty)
            XCTAssertGreaterThan(model.height, 100)
            XCTAssertLessThan(model.height, 160)
            let scroll = try XCTUnwrap(scrollViews(in: host).first)
            XCTAssertGreaterThanOrEqual(scroll.contentSize.height, 19)
            XCTAssertLessThanOrEqual(scroll.documentView?.frame.height ?? 0, scroll.contentSize.height + 1)
        }
    }

    @MainActor
    func testCompleteLongCardGrowsBeyondOneLineAndScrollsAtItsMaximumHeight() throws {
        let source = String(repeating: "Synthetic paragraph with enough words to wrap across several lines in the response card. ", count: 50)
        try withHostedCard(source: source) { model, host in
            XCTAssertEqual(model.height, 250, accuracy: 1)
            let scroll = try XCTUnwrap(scrollViews(in: host).first)
            XCTAssertGreaterThan(scroll.contentSize.height, 100, "The reply must not remain at its initial one-line height")
            XCTAssertLessThan(scroll.contentSize.height, model.height - 66, "Space must remain for the header and pinned action")
            XCTAssertGreaterThan(scroll.documentView?.frame.height ?? 0, scroll.contentSize.height * 3)
            XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 1)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: (scroll.documentView?.frame.height ?? 0) - scroll.contentSize.height))
            scroll.reflectScrolledClipView(scroll.contentView)
            XCTAssertGreaterThan(scroll.documentVisibleRect.minY, 0)
            XCTAssertEqual(model.height, 250, accuracy: 1, "Scrolling must not grow the card")
        }
    }

    @MainActor
    private func withHostedCard(
        source: String, inspect: (CardMeasurements, NSView) throws -> Void
    ) throws {
        let model = CardMeasurements()
        let host = NSHostingView(rootView: HostedResponseCard(model: model, source: source))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 270)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -3000, y: -3000))
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        // Geometry and state updates need actual rendering passes, not just fittingSize.
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            host.display()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        try inspect(model, host)
    }

    @MainActor
    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
}

@MainActor
private final class CardMeasurements: ObservableObject {
    @Published var height: CGFloat = 250
    var reportedHeights: [CGFloat] = []
}

private struct HostedResponseCard: View {
    @ObservedObject var model: CardMeasurements
    let source: String

    var body: some View {
        CodexResponseCard(
            source: source, isTruncated: false, projectName: "Fixture", chatTitle: "Synthetic conversation", launchError: nil,
            maximumHeight: 204,
            onHeightChange: { height in
                model.reportedHeights.append(height)
                model.height = min(250, height + 34 + 12)
            },
            onOpenCodex: {}, composer: nil
        )
        .padding(.top, 34)
        .frame(height: max(0, model.height - 12), alignment: .topLeading)
        .padding(.horizontal, 31)
        .padding(.bottom, 12)
        .background(.black)
        .frame(height: model.height, alignment: .top)
        .frame(width: 640, height: 270, alignment: .top)
        .preferredColorScheme(.dark)
    }
}
