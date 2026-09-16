//
//  CaptureModelsTests.swift
//  boringNotchTests
//
//  Covers the capture logic that has real decisions in it: normalising a drag,
//  rebasing a selection onto the right display, and reassembling Vision's
//  line fragments into text worth pasting.
//

import XCTest

@testable import boringNotch

final class CaptureModelsTests: XCTestCase {

    // MARK: - Selection

    func testSelectionNormalizesWhicheverWayTheUserDragged() {
        let downRight = SelectionRect(origin: CGPoint(x: 10, y: 10), current: CGPoint(x: 110, y: 60))
        let upLeft = SelectionRect(origin: CGPoint(x: 110, y: 60), current: CGPoint(x: 10, y: 10))

        XCTAssertEqual(downRight.rect, CGRect(x: 10, y: 10, width: 100, height: 50))
        XCTAssertEqual(upLeft.rect, downRight.rect, "a CGRect with a negative size captures nothing")
    }

    /// A stray click while aiming registers as a 1-2px drag. Capturing that
    /// produces a useless sliver of an image, so it is treated as a cancel.
    func testTinyDragsAreNotUsableSelections() {
        XCTAssertFalse(SelectionRect(origin: .zero, current: CGPoint(x: 3, y: 200)).isUsable, "too narrow")
        XCTAssertFalse(SelectionRect(origin: .zero, current: CGPoint(x: 200, y: 3)).isUsable, "too short")
        XCTAssertFalse(SelectionRect(origin: .zero, current: .zero).isUsable, "a click is not a drag")
        XCTAssertTrue(SelectionRect(origin: .zero, current: CGPoint(x: 20, y: 20)).isUsable)
    }

    func testSizeLabelRoundsToWholePixels() {
        let selection = SelectionRect(origin: .zero, current: CGPoint(x: 1280.4, y: 719.6))
        XCTAssertEqual(selection.sizeLabel, "1280 × 720")
    }

    // MARK: - Multi-display geometry

    /// A content filter's sourceRect is relative to its display, while the
    /// overlay works in global AppKit coordinates. Getting this wrong is
    /// invisible on a single-monitor Mac and captures the wrong region on
    /// every other one.
    func testSelectionIsRebasedOntoItsOwnDisplay() {
        let secondDisplay = CGRect(x: 1920, y: 0, width: 1512, height: 982)
        let selection = CGRect(x: 2020, y: 100, width: 200, height: 150)

        XCTAssertEqual(
            CaptureGeometry.sourceRect(forSelection: selection, in: secondDisplay),
            CGRect(x: 100, y: 100, width: 200, height: 150)
        )
    }

    func testRebasingHandlesDisplaysWithNegativeOrigins() {
        let leftDisplay = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
        let selection = CGRect(x: -1820, y: 200, width: 50, height: 50)

        XCTAssertEqual(
            CaptureGeometry.sourceRect(forSelection: selection, in: leftDisplay),
            CGRect(x: 100, y: 100, width: 50, height: 50)
        )
    }

    func testSelectionIsClampedToTheDisplay() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertEqual(
            CaptureGeometry.clamped(CGRect(x: -50, y: -50, width: 200, height: 200), to: display),
            display,
            "a drag past the edges asks only for pixels that exist"
        )
        XCTAssertEqual(
            CaptureGeometry.clamped(CGRect(x: 500, y: 500, width: 10, height: 10), to: display),
            .zero,
            "a fully off-display rect becomes empty rather than CGRect.null"
        )
    }

    // MARK: - Naming

    func testFilenameHasNoCharactersFinderShowsAsAPathSeparator() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current

        let name = CaptureNaming.filename(
            for: Date(timeIntervalSince1970: 1_789_000_325),
            kind: .area,
            fileExtension: "png",
            calendar: calendar
        )

        XCTAssertTrue(name.hasSuffix(".png"))
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"), "APFS allows it, but Finder renders it as '/'")
    }

    func testSanitizerReplacesIllegalCharactersAndNeverReturnsEmpty() {
        XCTAssertEqual(CaptureNaming.sanitized("a/b:c"), "a-b.c")
        XCTAssertEqual(CaptureNaming.sanitized("   "), "Screenshot")
        XCTAssertEqual(CaptureNaming.sanitized(""), "Screenshot")
    }

    // MARK: - OCR assembly

    private func line(
        _ text: String, y: CGFloat, x: CGFloat = 0.1, height: CGFloat = 0.04, confidence: Float = 0.9
    ) -> RecognizedLine {
        RecognizedLine(
            text: text,
            boundingBox: CGRect(x: x, y: y, width: 0.5, height: height),
            confidence: confidence
        )
    }

    /// Vision guarantees no ordering, so the assembler has to impose one.
    ///
    /// Spaced evenly on purpose: a large gap here would also trip paragraph
    /// detection and this test would stop being about sorting.
    func testLinesAreSortedTopToBottomRegardlessOfInputOrder() {
        let shuffled = [line("third", y: 0.78), line("first", y: 0.90), line("second", y: 0.84)]

        XCTAssertEqual(OCRTextAssembler.assemble(shuffled), "first\nsecond\nthird")
    }

    func testLinesOnTheSameRowReadLeftToRight() {
        let sameRow = [line("right", y: 0.90, x: 0.60), line("left", y: 0.90, x: 0.10)]

        XCTAssertEqual(OCRTextAssembler.assemble(sameRow), "left\nright")
    }

    /// Paragraph structure is the difference between pasteable text and a wall
    /// of lines, and Vision does not report it.
    func testAMuchLargerVerticalGapBecomesABlankLine() {
        let lines = [
            line("one", y: 0.90), line("two", y: 0.84), line("three", y: 0.78),
            line("far below", y: 0.40)
        ]

        XCTAssertEqual(OCRTextAssembler.assemble(lines), "one\ntwo\nthree\n\nfar below")
    }

    func testEvenlySpacedLinesStayOneParagraph() {
        let lines = [line("one", y: 0.90), line("two", y: 0.84), line("three", y: 0.78)]

        XCTAssertEqual(OCRTextAssembler.assemble(lines), "one\ntwo\nthree")
    }

    /// Vision happily "recognises" letterforms in textures and UI chrome at
    /// low confidence. Pasting that is worse than pasting nothing.
    func testLowConfidenceAndBlankFragmentsAreDropped() {
        let noisy = [
            line("real", y: 0.90),
            line("noise", y: 0.80, confidence: 0.1),
            line("   ", y: 0.70)
        ]

        XCTAssertEqual(OCRTextAssembler.assemble(noisy), "real")
    }

    func testNothingRecognisedGivesAnEmptyString() {
        XCTAssertEqual(OCRTextAssembler.assemble([]), "")
        XCTAssertEqual(OCRTextAssembler.assemble([line("  ", y: 0.5)]), "")
    }

    func testASingleLineNeedsNoGapHistory() {
        XCTAssertEqual(OCRTextAssembler.assemble([line("only", y: 0.5)]), "only")
    }

    /// Median rather than mean: one oversized gap (a heading) would drag a
    /// mean up far enough that no break is ever detected.
    func testMedian() {
        XCTAssertEqual(OCRTextAssembler.median([]), 0)
        XCTAssertEqual(OCRTextAssembler.median([5]), 5)
        XCTAssertEqual(OCRTextAssembler.median([1, 2, 3, 4]), 2.5)
        XCTAssertEqual(OCRTextAssembler.median([9, 1, 5]), 5, "sorts first")
    }

    // MARK: - Colour

    func testHexAndRGB() {
        XCTAssertEqual(SampledColor(red: 1, green: 0, blue: 0, alpha: 1).hex, "#FF0000")
        XCTAssertEqual(SampledColor(red: 1, green: 1, blue: 1, alpha: 1).hex, "#FFFFFF")
        XCTAssertEqual(SampledColor(red: 0, green: 0, blue: 0, alpha: 1).hex, "#000000")
        XCTAssertEqual(SampledColor(red: 0, green: 0.5, blue: 0.5, alpha: 1).hex, "#008080")
        XCTAssertEqual(SampledColor(red: 0, green: 0.75, blue: 1, alpha: 1).rgb, "rgb(0, 191, 255)")
    }

    func testHSL() {
        XCTAssertEqual(SampledColor(red: 1, green: 0, blue: 0, alpha: 1).hsl, "hsl(0, 100%, 50%)")
        XCTAssertEqual(SampledColor(red: 0, green: 0.5, blue: 0.5, alpha: 1).hsl, "hsl(180, 100%, 25%)")
        XCTAssertEqual(
            SampledColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1).hsl,
            "hsl(0, 0%, 50%)",
            "grey has no hue or saturation"
        )
    }

    /// A wide-gamut display can hand back components outside 0...1. Scaling
    /// those straight to a byte overflows and traps.
    func testOutOfGamutComponentsAreClamped() {
        let wide = SampledColor(red: 1.4, green: -0.3, blue: 0.5, alpha: 1)

        XCTAssertEqual(wide.hex, "#FF0080")
        XCTAssertEqual(wide.rgb, "rgb(255, 0, 128)")
    }

    func testFormatSelectionMatchesTheDedicatedProperties() {
        let color = SampledColor(red: 0.2, green: 0.55, blue: 0.9, alpha: 1)

        XCTAssertEqual(color.string(for: .hex), color.hex)
        XCTAssertEqual(color.string(for: .rgb), color.rgb)
        XCTAssertEqual(color.string(for: .hsl), color.hsl)
    }
}
