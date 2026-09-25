//
//  PreferenceCompatibilityTests.swift
//  boringNotchTests
//

import Foundation
import XCTest
@testable import boringNotch

final class PreferenceCompatibilityTests: XCTestCase {
    private let renamedKeys: [(String, String, Bool)] = [
        ("hudReplacement", "osdReplacement", false),
        ("inlineHUD", "inlineOSD", false),
        ("showOpenNotchHUD", "showOpenNotchOSD", true),
        ("showOpenNotchHUDPercentage", "showOpenNotchOSDPercentage", true),
        ("showClosedNotchHUDPercentage", "showClosedNotchOSDPercentage", false)
    ]

    private func withSuite(_ body: (UserDefaults, String) throws -> Void) throws {
        // Also namespace migrated keys: Foundation shares registration across suites.
        let name = "PreferenceCompatibilityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults, name)
    }

    private func checkEncodings<T: RawRepresentable & Equatable>(
        _ encodings: [(String, String, T)]
    ) throws where T.RawValue == String {
        try withSuite { defaults, _ in
            for (legacy, current, expected) in encodings {
                for encoded in [legacy, current] {
                    defaults.set(encoded, forKey: "enum")
                    let stored = try XCTUnwrap(defaults.string(forKey: "enum"))
                    let decoded = try XCTUnwrap(T(rawValue: stored))
                    XCTAssertEqual(decoded, expected)
                    XCTAssertEqual(decoded.rawValue, current)
                }
            }
            for invalid in ["", "unknown", "NOW PLAYING", " showOSD"] {
                XCTAssertNil(T(rawValue: invalid))
            }
        }
    }

    func testMediaControllerEncodings() throws {
        try checkEncodings([
            ("Now Playing", "nowPlaying", MediaControllerType.nowPlaying),
            ("Apple Music", "appleMusic", .appleMusic),
            ("Spotify", "spotify", .spotify),
            ("YouTube Music", "youtubeMusic", .youtubeMusic)
        ])
    }

    func testSneakPeekEncodings() throws {
        try checkEncodings([
            ("Default", "standard", SneakPeekStyle.standard),
            ("Inline", "inline", .inline)
        ])
    }

    func testOptionKeyEncodings() throws {
        try checkEncodings([
            ("Open System Settings", "openSettings", OptionKeyAction.openSettings),
            ("Show HUD", "showOSD", .showOSD),
            ("No Action", "none", .none)
        ])
    }

    func testSliderColorEncodings() throws {
        try checkEncodings([
            ("White", "white", SliderColorEnum.white),
            ("Match album art", "albumArt", .albumArt),
            ("Accent color", "accent", .accent)
        ])
    }

    func testLegacyBooleansMigrateOnceAndKeepUnrelatedValues() throws {
        for (legacy, current, _) in renamedKeys {
            for value in [false, true] {
                try withSuite { defaults, name in
                    let legacy = "\(name).\(legacy)"
                    let current = "\(name).\(current)"
                    defaults.set(value, forKey: legacy)
                    defaults.set("untouched", forKey: "unrelated")
                    XCTAssertEqual(PreferenceCompatibility.migratedKeyName(current, from: legacy, in: defaults), current)
                    XCTAssertEqual(defaults.object(forKey: current) as? Bool, value)
                    let migrated = defaults.persistentDomain(forName: name)
                    _ = PreferenceCompatibility.migratedKeyName(current, from: legacy, in: defaults)
                    XCTAssertEqual(defaults.persistentDomain(forName: name) as NSDictionary?, migrated as NSDictionary?)
                    XCTAssertEqual(defaults.object(forKey: legacy) as? Bool, value)
                    XCTAssertEqual(defaults.string(forKey: "unrelated"), "untouched")
                }
            }
        }
    }

    func testSavedCurrentBooleanWinsIncludingFalse() throws {
        for (legacy, current, _) in renamedKeys {
            for value in [false, true] {
                try withSuite { defaults, name in
                    let legacy = "\(name).\(legacy)"
                    let current = "\(name).\(current)"
                    defaults.set(!value, forKey: legacy)
                    defaults.set(value, forKey: current)
                    for _ in 0..<2 {
                        _ = PreferenceCompatibility.migratedKeyName(current, from: legacy, in: defaults)
                        XCTAssertEqual(defaults.object(forKey: current) as? Bool, value)
                    }
                }
            }
        }
    }

    func testAbsentKeysKeepFallbackWithoutPersistingIt() throws {
        for (legacy, current, fallback) in renamedKeys {
            try withSuite { defaults, name in
                let legacy = "\(name).\(legacy)"
                let current = "\(name).\(current)"
                _ = PreferenceCompatibility.migratedKeyName(current, from: legacy, in: defaults)
                XCTAssertNil(defaults.object(forKey: current))
                defaults.register(defaults: [current: fallback])
                XCTAssertEqual(defaults.bool(forKey: current), fallback)
                _ = PreferenceCompatibility.migratedKeyName(current, from: legacy, in: defaults)
                XCTAssertNil(defaults.persistentDomain(forName: name)?[current])
                XCTAssertNil(defaults.object(forKey: legacy))
            }
        }
    }
}

@MainActor
final class LegacyAppBundleMigrationTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("LegacyAppBundleMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try fileManager.removeItem(at: temporaryDirectory)
        }
    }

    func testMigratesOnlyTheLegacyProductName() throws {
        let legacyURL = temporaryDirectory
            .appendingPathComponent(LegacyAppBundleMigration.legacyBundleName, isDirectory: true)
        let destinationURL = temporaryDirectory
            .appendingPathComponent(LegacyAppBundleMigration.currentBundleName, isDirectory: true)
        let markerURL = legacyURL.appendingPathComponent("marker")
        try fileManager.createDirectory(at: legacyURL, withIntermediateDirectories: true)
        try Data("updated".utf8).write(to: markerURL)

        let migratedURL = try XCTUnwrap(
            LegacyAppBundleMigration.migrateIfNeeded(at: legacyURL, fileManager: fileManager)
        )

        XCTAssertEqual(migratedURL.standardizedFileURL, destinationURL.standardizedFileURL)
        XCTAssertFalse(fileManager.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(try Data(contentsOf: destinationURL.appendingPathComponent("marker")), Data("updated".utf8))
    }

    func testMigrationDestinationIsTheRenamedSibling() throws {
        let legacyURL = temporaryDirectory
            .appendingPathComponent(LegacyAppBundleMigration.legacyBundleName, isDirectory: true)

        XCTAssertEqual(
            LegacyAppBundleMigration.destinationURL(for: legacyURL)?.lastPathComponent,
            LegacyAppBundleMigration.currentBundleName
        )
        XCTAssertEqual(
            LegacyAppBundleMigration.destinationURL(for: legacyURL)?.deletingLastPathComponent(),
            temporaryDirectory.standardizedFileURL
        )
    }

    func testCurrentProductNameIsNotMoved() throws {
        let currentURL = temporaryDirectory
            .appendingPathComponent(LegacyAppBundleMigration.currentBundleName, isDirectory: true)
        try fileManager.createDirectory(at: currentURL, withIntermediateDirectories: true)

        XCTAssertNil(
            try LegacyAppBundleMigration.migrateIfNeeded(at: currentURL, fileManager: fileManager)
        )
        XCTAssertTrue(fileManager.fileExists(atPath: currentURL.path))
    }

    func testExistingDestinationIsNeverOverwritten() throws {
        let legacyURL = temporaryDirectory
            .appendingPathComponent(LegacyAppBundleMigration.legacyBundleName, isDirectory: true)
        let destinationURL = temporaryDirectory
            .appendingPathComponent(LegacyAppBundleMigration.currentBundleName, isDirectory: true)
        try fileManager.createDirectory(at: legacyURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try LegacyAppBundleMigration.migrateIfNeeded(at: legacyURL, fileManager: fileManager)
        )
        XCTAssertTrue(fileManager.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: destinationURL.path))
    }
}
