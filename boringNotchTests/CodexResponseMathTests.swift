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
    func testNativeMathRendersGlyphPixelsForGreekFractionsAndMatrices() throws {
        for latex in [#"\theta"#, #"p_\theta(x\mid z)"#, #"\frac{1}{\sqrt{2\pi}} e^{-x^2/2}"#, #"\begin{pmatrix}a&b\\c&d\end{pmatrix}"#] {
            let image = try XCTUnwrap(CodexMathImage.render(.init(latex: latex, isDisplay: true)), latex)
            let renderer = ImageRenderer(content: image)
            let pixels = try XCTUnwrap(renderer.cgImage)
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
    func testUnsupportedMathRemainsReadableInsteadOfDisappearing() {
        let equation = CodexMathEquation(latex: #"\unknowncommand{x}"#, isDisplay: false)
        XCTAssertNil(CodexMathImage.render(equation))
        let renderer = ImageRenderer(content: CodexMathImage.inlineImage(equation))
        XCTAssertGreaterThan(renderer.cgImage?.width ?? 0, 10)
    }
}
