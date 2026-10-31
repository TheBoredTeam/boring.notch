// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

//
//  ExtensionPackageTests.swift
//  boringNotchTests
//
import Security
import XCTest
@testable import boringNotch

final class ExtensionPackageTests: XCTestCase {
    func testValidPackageIsRecognizedWithoutLoadingItsBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bnplugin")
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["Contents/Resources", "Contents/MacOS"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let manifest = ExtensionManifest(id: "com.example.lyrics", name: "Lyrics", version: "1.0.0", apiVersion: 1)
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("Contents/Resources/manifest.json"))
        let info = ["CFBundleIdentifier": manifest.id, "CFBundleExecutable": "Lyrics"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: root.appendingPathComponent("Contents/Info.plist"))
        try Data("fixture".utf8).write(to: root.appendingPathComponent("Contents/MacOS/Lyrics"))
        let (parsed, executable) = try ExtensionPackage.inspect(root)
        XCTAssertEqual(parsed, manifest)
        XCTAssertEqual(executable.lastPathComponent, "Lyrics")
    }

    func testManifestRequiresSupportedAPIAndSafeIdentifier() throws {
        try ExtensionManifest(id: "com.example.free-extension", name: "Lyrics", version: "1.0", apiVersion: 1).validate()
        for id in ["../escape", "a/../../escape", "", "/tmp/plugin", "com.plugin/evil", "com.plugin\n"] {
            XCTAssertThrowsError(try ExtensionManifest(id: id, name: "Lyrics", version: "1.0", apiVersion: 1).validate())
        }
        XCTAssertThrowsError(try ExtensionManifest(id: "com.example.plugin", name: "Lyrics", version: "1", apiVersion: 2).validate())
    }

    func testUnsignedPackageCannotPassSignatureCheck() {
        XCTAssertThrowsError(try ExtensionPackage.verifySignature(at: URL(fileURLWithPath: "/tmp/nonexistent.bnplugin")))
    }

    func testPackageCannotUseExternalExecutableOrSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bnplugin")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        let manifest = ExtensionManifest(id: "com.example.plugin", name: "Example", version: "1", apiVersion: 1)
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("Contents/Resources/manifest.json"))
        let info = ["CFBundleIdentifier": manifest.id, "CFBundleExecutable": "../../outside"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: root.appendingPathComponent("Contents/Info.plist"))
        XCTAssertThrowsError(try ExtensionPackage.inspect(root))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertThrowsError(try ExtensionPackage.inspect(root))
    }
    func testAnyPublisherCanBeApprovedButIdentityChangesRequireReview() throws {
        let suite = "extension-trust-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let independent = ExtensionPublisher(teamID: "INDEPENDENT", name: "Independent Developer", isDevelopment: false)
        let other = ExtensionPublisher(teamID: "DIFFERENT", name: "Another Developer", isDevelopment: false)
        XCTAssertFalse(ExtensionTrustStore.isApproved(independent, for: "com.example.free", defaults: defaults))
        ExtensionTrustStore.approve(independent, for: "com.example.free", defaults: defaults)
        XCTAssertTrue(ExtensionTrustStore.isApproved(independent, for: "com.example.free", defaults: defaults))
        XCTAssertFalse(ExtensionTrustStore.isApproved(other, for: "com.example.free", defaults: defaults))
        XCTAssertFalse(ExtensionTrustStore.isApproved(independent, for: "com.example.other", defaults: defaults))
        ExtensionTrustStore.remove("com.example.free", defaults: defaults)
        XCTAssertFalse(ExtensionTrustStore.isApproved(independent, for: "com.example.free", defaults: defaults))
    }

    func testPublisherRequirementAndActivityModes() throws {
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(ExtensionPackage.publisherRequirement as CFString, [], &requirement), errSecSuccess)
        let legacy = Data(#"{"id":"com.example.free","name":"Free","version":"1","apiVersion":1}"#.utf8)
        let always = try JSONDecoder().decode(ExtensionManifest.self, from: legacy)
        XCTAssertNil(always.capabilities)
        var withActivities = always
        withActivities.capabilities = ["liveActivities"]
        try withActivities.validate()
        XCTAssertTrue(always.receivesUpdates(locked: false, awake: true, sessionActive: true, requested: true))
        var locked = always; locked.activation = .lockScreen
        XCTAssertFalse(locked.receivesUpdates(locked: false, awake: true, sessionActive: true, requested: true))
        XCTAssertTrue(locked.receivesUpdates(locked: true, awake: true, sessionActive: true, requested: true))
        XCTAssertFalse(locked.receivesUpdates(locked: true, awake: false, sessionActive: true, requested: true))
        XCTAssertFalse(always.receivesUpdates(locked: false, awake: true, sessionActive: true, requested: false))
    }

}
