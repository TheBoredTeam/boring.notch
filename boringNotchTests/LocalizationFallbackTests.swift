//
//  LocalizationFallbackTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

/// Guards against raw identifiers such as "osd_sources_built_in" leaking into the UI.
///
/// Several settings strings are only translated in a subset of locales. A regional
/// English locale like en-IN resolves to `en-GB.lproj`, and where that catalog lacks a
/// key `NSLocalizedString` returns the key itself, which then renders verbatim in the
/// settings window.
final class LocalizationFallbackTests: XCTestCase {
    /// Every snake_case key used through `localizedOrEnglish`, with its English text.
    private let expected: [String: String] = [
        "osd_sources_built_in": "Built-in",
        "option_key_open_system_settings": "Open System Settings",
        "option_key_show_osd": "Show OSD",
        "option_key_no_action": "No action",
        "sneak_peek_standard": "Default",
        "sneak_peek_inline": "Inline",
        "slider_color_white": "White",
        "slider_color_album_art": "Match album art",
        "slider_color_accent": "Accent color",
    ]

    func testFallbackResolvesEveryKey() {
        for (key, english) in expected {
            let value = localizedOrEnglish(key)
            XCTAssertNotEqual(value, key, "\(key) resolved to the raw key")
            XCTAssertFalse(value.isEmpty, "\(key) resolved to an empty string")
            XCTAssertEqual(value, english, "\(key) did not resolve to its English text")
        }
    }

    /// The English catalog is the fallback's backstop, so it must actually be present in
    /// the built bundle and contain every key.
    func testEnglishCatalogContainsEveryKey() {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
              let englishBundle = Bundle(path: path)
        else {
            return XCTFail("en.lproj is missing from the app bundle")
        }

        for (key, english) in expected {
            let value = englishBundle.localizedString(forKey: key, value: key, table: nil)
            XCTAssertEqual(value, english, "en.lproj is missing \(key)")
        }
    }

    /// Reproduces the actual failure: en-GB is missing these keys, so a bare lookup there
    /// returns the raw key. If this ever starts passing, Crowdin has filled the gap and
    /// the fallback has become belt-and-braces rather than load-bearing.
    func testEnGBIsTheLocaleThatNeedsTheFallback() {
        guard let path = Bundle.main.path(forResource: "en-GB", ofType: "lproj"),
              let gbBundle = Bundle(path: path)
        else {
            return XCTFail("en-GB.lproj is missing from the app bundle")
        }

        let rawKeyLookups = expected.keys.filter { key in
            gbBundle.localizedString(forKey: key, value: key, table: nil) == key
        }

        XCTAssertFalse(
            rawKeyLookups.isEmpty,
            "en-GB now covers every key; the fallback is no longer load-bearing"
        )
    }
}
