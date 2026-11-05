import AppKit
import SwiftUI
import XCTest
@testable import CodexResponseRendering

final class CodexResponseMathTests: XCTestCase {
    func testParenthesisAndBracketMathSurviveMarkdownEscaping() {
        let source = #"The variable \(\theta\) appears in \(p_\theta(x\mid z)\)."# + "\n\n" + #"\[p_\theta(x\mid z)=\frac{1}{2}\]"#
        let document = CodexMathDocument(source: source)
        XCTAssertEqual(document.equations.count, 3)
        XCTAssertEqual(Set(document.equations.values.map(\.latex)), [#"\theta"#, #"p_\theta(x\mid z)"#, #"p_\theta(x\mid z)=\frac{1}{2}"#])
        XCTAssertEqual(document.equations.values.filter(\.isDisplay).count, 1)
        XCTAssertFalse(document.markdown.contains(#"\("#))
        XCTAssertTrue(document.markdown.contains("boringnotch-math://equation/"))
    }

    func testDollarMathAndCurrencyAreDistinguished() {
        let math = CodexMathDocument(source: #"Use $x_1$ and $$\sum_{i=1}^{n} x_i$$."#)
        XCTAssertEqual(math.equations.count, 2)
        XCTAssertEqual(math.equations.values.filter(\.isDisplay).count, 1)
        let mixed = CodexMathDocument(source: #"Prices are $5 and $10; the variable is $x$."#)
        XCTAssertEqual(mixed.equations.values.map(\.latex), ["x"])
        for source in ["It costs $5 and $10.", #"The literal price is \$5."#, #"Unfinished \(\frac{x}{"#] {
            let document = CodexMathDocument(source: source)
            XCTAssertTrue(document.equations.isEmpty)
            XCTAssertEqual(document.markdown, source)
        }
    }

    func testCommonMarkCodeLinksAndImagesAreNotRewrittenAsMath() {
        let protected = #"""
        ```latex
        \(\theta\)
        $$x^2$$
        ```

        ~~~text
        \[x_1\]
        ~~~

        你好 🙂 `\(x\)` and ``$y$``.

            \(z\)

        [link](https://example.invalid/$x$)
        ![\(alt\)](https://example.invalid/image.png)
        """#
        let document = CodexMathDocument(source: protected)
        XCTAssertTrue(document.equations.isEmpty)
        XCTAssertEqual(document.markdown, protected)
        let mixed = CodexMathDocument(source: protected + "\n\n" + #"Actual \(\alpha\)."#)
        XCTAssertEqual(mixed.equations.values.map(\.latex), [#"\alpha"#])
        let unfinishedFence = CodexMathDocument(source: "```latex\n" + #"\(literal\)"#)
        XCTAssertTrue(unfinishedFence.equations.isEmpty)
    }

    func testLocalEquationIdentifiersAreStableAndContainNoSourceText() {
        let first = CodexMathDocument(source: #"\(\theta\)"#)
        let same = CodexMathDocument(source: #"\(\theta\)"#)
        let other = CodexMathDocument(source: #"\(\alpha\)"#)
        XCTAssertEqual(first.equations.keys.first, same.equations.keys.first)
        XCTAssertNotEqual(first.equations.keys.first, other.equations.keys.first)
        XCTAssertFalse(first.equations.keys.first!.absoluteString.contains("theta"))
    }

    @MainActor
    private func rendered(_ latex: String, display: Bool = true) async throws -> Image {
        let image = await CodexMathImage.render(.init(latex: latex, isDisplay: display))
        return try XCTUnwrap(image, latex)
    }

    @MainActor
    func testMathRendersGlyphPixelsForGreekFractionsAndMatrices() async throws {
        for latex in [#"\frac{1}{2}"#, #"\frac{1.5}{2.25}"#, #"\theta"#, #"p_\theta(x\mid z)"#, #"\frac{1}{\sqrt{2\pi}} e^{-x^2/2}"#, #"\begin{pmatrix}a&b\\c&d\end{pmatrix}"#] {
            let image = try await rendered(latex)
            let pixels = try XCTUnwrap(ImageRenderer(content: image).cgImage)
            XCTAssertGreaterThan(pixels.width, 2)
            XCTAssertGreaterThan(pixels.height, 4)
            var buffer = [UInt8](repeating: 0, count: pixels.width * pixels.height * 4)
            let context = try XCTUnwrap(CGContext(
                data: &buffer, width: pixels.width, height: pixels.height, bitsPerComponent: 8,
                bytesPerRow: pixels.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(pixels, in: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
            XCTAssertTrue(stride(from: 3, to: buffer.count, by: 4).contains { buffer[$0] > 0 }, "Math must contain glyph pixels")
        }
    }

    @MainActor
    func testUnsupportedMathRemainsReadableInsteadOfDisappearing() async {
        let equation = CodexMathEquation(latex: #"\unknowncommand{x}"#, isDisplay: false)
        let result = await CodexMathImage.render(equation)
        XCTAssertNil(result)
        let fallback = await CodexMathImage.inlineImage(equation)
        let renderer = ImageRenderer(content: fallback)
        XCTAssertGreaterThan(renderer.cgImage?.width ?? 0, 10)
    }

    @MainActor
    func testEncoderFlowRendersLabeledArrowsAndBoldVectors() async throws {
        let latex = #"\mathbf x \;\xrightarrow{\text{encoder}}\; \boldsymbol\mu_\phi(\mathbf x),\ \mathbf s_\phi(\mathbf x) \;\longrightarrow\; q_\phi(\mathbf z\mid\mathbf x)."#
        let image = try await rendered(latex)
        for command in [#"\xrightarrow{\text{encoder}}"#, #"\underbrace{x}_{\text{input}}"#, #"\left[x\middle\|y\right]"#] {
            _ = try await rendered(command)
        }
        try capture(image, to: "/tmp/boring-notch-encoder-flow.png")
    }

    @MainActor
    func testKLDivergenceRendersAnnotatedUnderbraces() async throws {
        let latex = #"D_{\mathrm{KL}}\left[\underbrace{q_\phi(\mathbf z\mid\mathbf x)}_{\text{codes predicted for this image}}\;\middle\|\;\underbrace{p(\mathbf z)}_{\text{prior over codes}}\right]."#
        let image = try await rendered(latex)
        let plain = try await rendered(#"D_{\mathrm{KL}}\left[q_\phi(\mathbf z\mid\mathbf x)\middle\|p(\mathbf z)\right]."#)
        let pixels = try XCTUnwrap(ImageRenderer(content: image).cgImage)
        let plainPixels = try XCTUnwrap(ImageRenderer(content: plain).cgImage)
        XCTAssertGreaterThan(pixels.height, plainPixels.height, "Annotations must remain below the braces")
        try capture(image, to: "/tmp/boring-notch-annotated-kl.png")
    }

    @MainActor
    func testGaussianNotationWithBoldGreekAndNamedOperators() async throws {
        for latex in [
            #"\mathcal N\!\left(\mathbf y;\mu_i,\mathrm{diag}(\mathbf v_i^2)\right)"#,
            #"\boldsymbol\alpha_i"#, #"\operatorname{diag}(\mathbf v_i^2)"#
        ] {
            _ = try await rendered(latex)
        }
        let image = try await rendered(#"r_i(\mathbf y)=\mathcal N\!\left(\mathbf y;\boldsymbol\alpha_i,\operatorname{diag}(\mathbf v_i^2)\right)."#)
        try capture(image, to: "/tmp/boring-notch-gaussian-math.png")
    }

    @MainActor
    func testNamedOperatorsAndBoldSymbolsKeepParsingAndErrors() async throws {
        for latex in [#"\operatorname{Cov}(X,Y)"#, #"\operatorname*{arg\,max}_{x}f(x)"#, #"\frac{\boldsymbol{\alpha}}{\operatorname{Var}(X)}"#] {
            _ = try await rendered(latex, display: false)
        }
        for latex in [#"\operatorname{diag"#, #"\boldsymbol{"#, #"\color{invalid}{x}"#] {
            let image = await CodexMathImage.render(.init(latex: latex, isDisplay: true))
            XCTAssertNil(image, latex)
        }
    }

    @MainActor
    func testBoxedLossWithWideHatUsesTypesetGlyphsAndAFrame() async throws {
        let inner = #"\widehat{\text{Loss}}(\mathbf{x})=-\log p_\theta(\mathbf{x}\mid\mathbf{z})+D_{\mathrm{KL}}\left[q_\phi(\mathbf{z}\mid\mathbf{x})\Vert p(\mathbf{z})\right]"#
        let plain = try await rendered(inner)
        let boxed = try await rendered("\\boxed{\n" + inner + "\n}")
        let plainPixels = try XCTUnwrap(ImageRenderer(content: plain).cgImage)
        let boxedPixels = try XCTUnwrap(ImageRenderer(content: boxed).cgImage)
        XCTAssertGreaterThan(boxedPixels.width, plainPixels.width)
        XCTAssertGreaterThan(boxedPixels.height, plainPixels.height)
        try capture(boxed, to: "/tmp/boring-notch-boxed-math.png")
    }

    @MainActor
    func testBoxesHandleWhitespaceNestedGroupsAndEscapedBraces() async throws {
        for latex in [#"\boxed {\frac{x_1}{y^2}}"#, #"\boxed{\left\{x\right\}}"#, #"\boxed{x} + \boxed{y}"#] {
            _ = try await rendered(latex)
        }
        _ = try await rendered(#"\boxed{x^2}"#, display: false)
        for latex in [#"\boxed{\frac{x}{y}"#, #"\boxed{x} + \unknowncommand{y}"#] {
            let image = await CodexMathImage.render(.init(latex: latex, isDisplay: true))
            XCTAssertNil(image, latex)
        }
    }

    @MainActor
    func testMathCannotLoadExternalContentOrExceedBitmapBounds() async throws {
        for latex in [
            #"\href{https://example.invalid}{x}"#,
            #"\includegraphics{file:///tmp/fixture.png}"#,
            #"\require{html}"#,
            #"\rule{5000em}{1em}"#,
            String(repeating: "x", count: 65537)
        ] {
            let image = await CodexMathImage.render(.init(latex: latex, isDisplay: true))
            XCTAssertNil(image)
        }
        // A rejected expression must not poison subsequent conversion or its cache.
        _ = try await rendered(#"\frac{x}{y}"#)
        _ = try await rendered(#"\frac{x}{y}"#)
    }

    @MainActor
    func testMathInEmphasizedListLabelsRemainsVisible() async throws {
        var referenceInk = 0
        for wrapper in ["", "**", "*", "***", "~~"] {
            let source = "- " + wrapper + #"\(\mu_\theta(z_t,t)\)"# + wrapper + ": next mean."
            let host = NSHostingView(rootView: CodexResponseMarkdown(source: source, onOpenCodex: {})
                .frame(width: 400, alignment: .leading).padding(8).background(.black).preferredColorScheme(.dark))
            host.frame = NSRect(x: 0, y: 0, width: 416, height: 80)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.setFrameOrigin(NSPoint(x: -3000, y: -3000))
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            for _ in 0..<50 {
                host.layoutSubtreeIfNeeded()
                host.display()
                try await Task.sleep(for: .milliseconds(20))
            }
            let pixels = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: pixels)
            var ink = 0
            for x in 0..<pixels.pixelsWide {
                for y in 0..<pixels.pixelsHigh {
                    if (pixels.colorAt(x: x, y: y)?.redComponent ?? 0) > 0.3 {
                        ink += 1
                    }
                }
            }
            if wrapper.isEmpty { referenceInk = ink }
            XCTAssertGreaterThan(referenceInk, 100)
            XCTAssertEqual(Double(ink), Double(referenceInk), accuracy: Double(referenceInk) * 0.1,
                           "Styled list math must retain the same glyphs as plain inline math")
            try XCTUnwrap(pixels.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/boring-notch-inline-\(wrapper == "~~" ? "strike" : String(wrapper.count)).png"))
        }
    }

    @MainActor
    func testHostedResponseRendersMathAndKeepsComposerAndFooterVisible() async throws {
        let encoder = #"\mathbf x \;\xrightarrow{\text{encoder}}\; \boldsymbol\mu_\phi(\mathbf x),\ \mathbf s_\phi(\mathbf x) \;\longrightarrow\; q_\phi(\mathbf z\mid\mathbf x)."#
        let divergence = #"D_{\mathrm{KL}}\left[\underbrace{q_\phi(\mathbf z\mid\mathbf x)}_{\text{codes predicted for this image}}\;\middle\|\;\underbrace{p(\mathbf z)}_{\text{prior over codes}}\right]."#
        let source = "The encoder predicts a distribution for each input.\n\n\\[" + encoder + "\\]\n\nThe prior is independent of the input.\n\n\\[" + divergence + "\\]"
        let notation = #"""
        - **\(z_t\)**: the current noisy image.
        - **\(\mu_\theta(z_t,t)\)**: the next image's mean.
        - **\(\xi_t \sim \mathcal{N}(0,I)\)**: fresh Gaussian noise.
        - **\(\sigma_t\)**: controls how much randomness we add.

        The Gaussian forward result is exact. :codex-annotation{index="1"}
        """#
        for (name, content) in [("math", source), ("short", "Got it."), ("notation", notation)] {
            let host = NSHostingView(rootView:
                CodexResponseCard(
                    source: content, isTruncated: false, projectName: "Fixture", chatTitle: "Synthetic math example",
                    launchError: nil, maximumHeight: 264, onHeightChange: { _ in }, onOpenCodex: {},
                    composer: AnyView(CodexReplyComposer(
                        text: .constant(""), chatTitle: "Synthetic math example", canSend: false,
                        isEditable: true, isSending: false, acknowledgement: nil,
                        onSend: {}, onDismiss: {}, onFocusChange: { _ in }, onInteraction: {}
                    ))
                )
                .padding(.top, 34).padding(.bottom, 12)
                .frame(width: 640).background(.black).preferredColorScheme(.dark)
            )
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 310)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.setFrameOrigin(NSPoint(x: -3000, y: -3000))
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            // Let asynchronous typesetting and geometry reporting reach the real host.
            for _ in 0..<50 {
                host.layoutSubtreeIfNeeded()
                host.display()
                try await Task.sleep(for: .milliseconds(20))
            }
            let size = host.fittingSize
            XCTAssertLessThanOrEqual(size.height, 310)
            XCTAssertGreaterThan(size.height, name == "short" ? 100 : 200)
            host.setFrameSize(size)
            host.layoutSubtreeIfNeeded()
            let pixels = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: pixels)
            try XCTUnwrap(pixels.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/boring-notch-" + name + "-final-card.png"))
        }
    }

    @MainActor
    private func capture(_ image: Image, to path: String) throws {
        let pixels = try XCTUnwrap(ImageRenderer(content: image.padding(16).background(.black)).cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: pixels).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: path))
    }
}
