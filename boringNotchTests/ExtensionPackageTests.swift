//
//  ExtensionPackageTests.swift
//  boringNotchTests
//
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
        try ExtensionManifest(id: "theboringteam.lockscreen-lyrics", name: "Lyrics", version: "1.0", apiVersion: 1).validate()
        for id in ["../escape", "a/../../escape", "", "/tmp/plugin", "com.plugin/evil"] {
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
}
