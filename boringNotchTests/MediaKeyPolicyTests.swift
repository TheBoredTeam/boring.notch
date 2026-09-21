import XCTest
@testable import boringNotch

final class MediaKeyPolicyTests: XCTestCase {
    func testDisabledAndUnsupportedControlsPassThrough() {
        XCTAssertEqual(disposition(.soundUp, enabled: false), .passThrough)
        XCTAssertEqual(disposition(.soundUp, volume: false), .passThrough)
        XCTAssertEqual(disposition(.brightnessUp, brightness: false), .passThrough)
        XCTAssertEqual(disposition(.keyboardBrightnessUp, backlight: false), .passThrough)
    }

    func testSelectedProviderOwnsAction() {
        XCTAssertEqual(disposition(.soundUp, source: .builtin), .handle)
        XCTAssertEqual(disposition(.soundUp, source: .betterDisplay), .passThrough)
        XCTAssertEqual(disposition(.brightnessUp, source: .lunar), .passThrough)
    }

    func testCommandVolumePassesThroughAndCommandBrightnessIsExplicitBacklight() {
        XCTAssertEqual(disposition(.soundUp, modifiers: .command), .passThrough)
        XCTAssertEqual(disposition(.mute, modifiers: .command), .passThrough)
        XCTAssertEqual(
            disposition(.brightnessUp, modifiers: .command, source: .betterDisplay),
            .handle)
        XCTAssertEqual(
            disposition(
                .brightnessUp, modifiers: .command, source: .betterDisplay,
                backlight: false),
            .passThrough)
    }

    func testNativeShiftFeedbackTable() {
        let cases: [(preference: Bool, shift: Bool, expected: Bool)] = [
            (false, false, false),
            (false, true, true),
            (true, false, true),
            (true, true, false),
        ]
        for item in cases {
            let modifiers: MediaKeyModifiers = item.shift ? .shift : []
            XCTAssertEqual(
                MediaKeyPolicy.shouldPlayVolumeFeedback(
                    preferenceEnabled: item.preference, modifiers: modifiers),
                item.expected)
        }
    }

    func testNormalAndFineStepModifiersRemainDistinct() {
        XCTAssertEqual(MediaKeyPolicy.stepDivisor(modifiers: []), 1)
        XCTAssertEqual(MediaKeyPolicy.stepDivisor(modifiers: .option), 1)
        XCTAssertEqual(MediaKeyPolicy.stepDivisor(modifiers: [.option, .shift]), 4)
    }

    func testStopInvalidatesAsynchronousStartCompletionAndReenable() {
        var lifecycle = MediaKeyTapLifecycle()
        let first = lifecycle.beginStart()
        lifecycle.stop()
        XCTAssertFalse(lifecycle.acceptsCompletion(generation: first))
        XCTAssertFalse(lifecycle.desiredEnabled)

        let second = lifecycle.beginStart()
        XCTAssertTrue(lifecycle.acceptsCompletion(generation: second))
        XCTAssertFalse(lifecycle.acceptsCompletion(generation: first))
    }

    private func disposition(
        _ key: MediaKeyKind, modifiers: MediaKeyModifiers = [], enabled: Bool = true,
        source: OSDControlSource = .builtin, volume: Bool = true,
        brightness: Bool = true, backlight: Bool = true
    ) -> MediaKeyDisposition {
        MediaKeyPolicy.disposition(
            for: key, modifiers: modifiers, replacementEnabled: enabled,
            selectedSource: source, volumeSupported: volume,
            brightnessSupported: brightness, backlightSupported: backlight)
    }
}
