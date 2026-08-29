//
//  BundleIDResolverTests.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Covers the app-side bundle-ID resolver: normalization parity with the
//  helper, the direct-probe and directory-scan fallbacks against an injected
//  fixture directory, and memoization of hits and misses.
//

import XCTest
@testable import boringNotch

final class BundleIDResolverTests: XCTestCase {

    private var resolver: BundleIDResolver!
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        resolver = BundleIDResolver()
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundleIDResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
        fixtureRoot = nil
        resolver = nil
        try super.tearDownWithError()
    }

    /// Builds a minimal `.app` — just `Contents/Info.plist` with a bundle ID,
    /// optionally a display name — inside the fixture root.
    @discardableResult
    private func makeFixtureApp(named name: String, bundleID: String, displayName: String? = nil) throws -> URL {
        let appURL = fixtureRoot.appendingPathComponent(name).appendingPathExtension("app")
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": bundleID]
        if let displayName { info["CFBundleDisplayName"] = displayName }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return appURL
    }

    // MARK: - Normalization

    func testNormalizationStripsBidiMarksCaseAndWhitespace() {
        XCTAssertEqual(BundleIDResolver.normalizedAppName("WhatsApp"), "whatsapp")
        XCTAssertEqual(BundleIDResolver.normalizedAppName("whatsapp"), "whatsapp")
        // WhatsApp's localizedName really is "\u{200E}WhatsApp" (LRM prefix).
        XCTAssertEqual(BundleIDResolver.normalizedAppName("\u{200E}WhatsApp"), "whatsapp")
        XCTAssertEqual(BundleIDResolver.normalizedAppName(" \u{202A}WhatsApp\u{202C}\u{2068} "), "whatsapp")
        XCTAssertEqual(
            BundleIDResolver.normalizedAppName("WhatsApp"),
            BundleIDResolver.normalizedAppName("\u{200E}whatsapp")
        )
    }

    // MARK: - Direct probe

    /// `<dir>/<Name>.app` exists: the probe must hit before any directory
    /// listing is needed.
    func testDirectProbeFindsFixture() throws {
        let name = "ProbeFixture\(UUID().uuidString.prefix(8))"
        let bundleID = "com.test.probe.\(name)"
        try makeFixtureApp(named: name, bundleID: bundleID)

        XCTAssertEqual(resolver.bundleID(forAppNamed: name, searchDirectories: [fixtureRoot]), bundleID)
    }

    // MARK: - Directory scan

    /// The .app's filename doesn't match the queried name, so only the scan's
    /// CFBundleDisplayName comparison can find it.
    func testDirectoryScanMatchesDisplayName() throws {
        let tag = UUID().uuidString.prefix(8)
        let displayName = "Scan Fixture \(tag)"
        let bundleID = "com.test.scan.\(tag)"
        try makeFixtureApp(named: "scanfixture-\(tag)", bundleID: bundleID, displayName: displayName)

        XCTAssertEqual(resolver.bundleID(forAppNamed: displayName, searchDirectories: [fixtureRoot]), bundleID)
    }

    /// Filename match through normalization: lowercase query with a bidi mark
    /// must still match the capitalized .app name.
    func testDirectoryScanMatchesFilenameIgnoringCaseAndBidiMarks() throws {
        let name = "BidiFixture\(UUID().uuidString.prefix(8))"
        let bundleID = "com.test.bidi.\(name)"
        try makeFixtureApp(named: name, bundleID: bundleID)

        XCTAssertEqual(
            resolver.bundleID(forAppNamed: "\u{200E}\(name.lowercased())", searchDirectories: [fixtureRoot]),
            bundleID
        )
    }

    // MARK: - Misses

    func testNoMatchReturnsNil() {
        let name = "DefinitelyNotARealApp-\(UUID().uuidString)"
        XCTAssertNil(resolver.bundleID(forAppNamed: name, searchDirectories: [fixtureRoot]))
    }

    func testEmptyAndWhitespaceNamesReturnNil() {
        XCTAssertNil(resolver.bundleID(forAppNamed: ""))
        XCTAssertNil(resolver.bundleID(forAppNamed: "   "))
        XCTAssertNil(resolver.bundleID(forAppNamed: "\u{200E}"))
    }

    // MARK: - Cache

    /// After the first (disk) resolution, deleting the fixture must not change
    /// the answer — proof the second call never touches the directory again.
    func testSecondResolutionComesFromCache() throws {
        let name = "CacheFixture\(UUID().uuidString.prefix(8))"
        let bundleID = "com.test.cache.\(name)"
        let appURL = try makeFixtureApp(named: name, bundleID: bundleID)

        XCTAssertEqual(resolver.bundleID(forAppNamed: name, searchDirectories: [fixtureRoot]), bundleID)

        try FileManager.default.removeItem(at: appURL)
        XCTAssertEqual(resolver.bundleID(forAppNamed: name, searchDirectories: [fixtureRoot]), bundleID)
    }

    /// Negative results are cached too: a miss followed by the app appearing
    /// on disk must still answer the cached miss rather than rescanning.
    func testNegativeResultIsCached() throws {
        let name = "LateFixture\(UUID().uuidString.prefix(8))"
        XCTAssertNil(resolver.bundleID(forAppNamed: name, searchDirectories: [fixtureRoot]))

        try makeFixtureApp(named: name, bundleID: "com.test.late.\(name)")
        XCTAssertNil(resolver.bundleID(forAppNamed: name, searchDirectories: [fixtureRoot]))
    }
}
