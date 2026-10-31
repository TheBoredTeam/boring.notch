// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Foundation
import XCTest
@testable import boringNotch

final class ExtensionArchiveTests: XCTestCase {
    private struct Entry {
        let path: String
        var data = Data()
        var mode: UInt32 = 0o100644
        var declaredSize: UInt32?
        var flags: UInt16 = 0
    }

    private func packageEntries() throws -> [Entry] {
        let manifest = ExtensionManifest(id: "com.example.activity", name: "Activity", version: "1", apiVersion: 1)
        let info = ["CFBundleIdentifier": manifest.id, "CFBundleExecutable": "Activity"]
        let root = "com.example.activity.bnplugin/Contents/"
        return [
            Entry(path: root + "Info.plist", data: try PropertyListSerialization.data(
                fromPropertyList: info, format: .xml, options: 0)),
            Entry(path: root + "Resources/manifest.json", data: try JSONEncoder().encode(manifest)),
            Entry(path: root + "MacOS/Activity", data: Data("fixture".utf8), mode: 0o100755)
        ]
    }

    func testZIPInstallsOneBundleAndReleasesStaging() throws {
        let url = try archive(try packageEntries())
        defer { try? FileManager.default.removeItem(at: url) }
        let prepared = try ExtensionArchive.prepare(url)
        let manifest = try ExtensionPackage.inspect(prepared.url).0
        XCTAssertEqual(manifest.id, "com.example.activity")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath:
            prepared.url.appendingPathComponent("Contents/MacOS/Activity").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.url.path))
        prepared.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.url.path))
    }

    func testFinderMetadataDoesNotBecomeAnInstalledPackage() throws {
        var entries = try packageEntries()
        entries.append(Entry(path: "__MACOSX/._com.example.activity.bnplugin", data: Data("metadata".utf8)))
        entries.append(Entry(path: "com.example.activity.bnplugin/Contents/._Info.plist", data: Data("metadata".utf8)))
        entries.append(Entry(path: ".DS_Store", data: Data("metadata".utf8)))
        let url = try archive(entries)
        defer { try? FileManager.default.removeItem(at: url) }
        let prepared = try ExtensionArchive.prepare(url)
        defer { prepared.cleanup() }
        XCTAssertEqual(prepared.url.lastPathComponent, "com.example.activity.bnplugin")
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            prepared.url.appendingPathComponent("Contents/._Info.plist").path))
    }

    func testRejectsTraversalAbsoluteAndAmbiguousPathsBeforeWriting() throws {
        let escaped = "extension-escape-" + UUID().uuidString
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(escaped)
        for path in ["../" + escaped, "/tmp/" + escaped, "bundle/../" + escaped,
                     "bundle\\" + escaped, "bundle//" + escaped, "bundle/./" + escaped,
                     "C:/" + escaped] {
            try assertRejected(try packageEntries() + [Entry(path: path, data: Data("bad".utf8))])
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
    }

    func testRejectsSymlinksAndSpecialFiles() throws {
        for mode: UInt32 in [0o120777, 0o020644] {
            try assertRejected(try packageEntries() + [Entry(
                path: "com.example.activity.bnplugin/link", data: Data("/tmp".utf8), mode: mode)])
        }
    }

    func testFIFOEncodedEntryCannotCreateAPipe() throws {
        // libarchive treats a ZIP's FIFO attribute as a regular file. Our
        // writer must still create only an ordinary file, never a named pipe.
        let url = try archive(try packageEntries() + [Entry(
            path: "com.example.activity.bnplugin/pipe", data: Data("harmless".utf8), mode: 0o010644)])
        defer { try? FileManager.default.removeItem(at: url) }
        let prepared = try ExtensionArchive.prepare(url)
        defer { prepared.cleanup() }
        let attributes = try FileManager.default.attributesOfItem(atPath:
            prepared.url.appendingPathComponent("pipe").path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeRegular)
    }

    func testRejectsDuplicatePathsAndCaseAliasedParents() throws {
        let entries = try packageEntries()
        try assertRejected(entries + [entries[0]])
        try assertRejected(entries + [Entry(path: "com.example.activity.bnplugin/contents/extra")])
        try assertRejected(entries + [Entry(path: "com.example.activity.bnplugin/Contents/info.plist")])
    }

    func testRejectsEncryptedOversizedAndMultiplePackages() throws {
        try assertRejected(try packageEntries() + [Entry(
            path: "com.example.activity.bnplugin/encrypted", flags: 1)])
        try assertRejected(try packageEntries() + [Entry(
            path: "com.example.activity.bnplugin/bomb", declaredSize: UInt32(ExtensionPackage.maximumBytes + 1))])
        try assertRejected(try packageEntries() + [Entry(path: "another.bnplugin/file")])
    }

    func testRejectsTruncatedOrCorruptZIP() throws {
        let url = try archive(try packageEntries())
        defer { try? FileManager.default.removeItem(at: url) }
        var bytes = try Data(contentsOf: url)
        bytes = bytes.prefix(20)
        try bytes.write(to: url)
        XCTAssertThrowsError(try ExtensionArchive.prepare(url))
    }

    private func assertRejected(_ entries: [Entry], file: StaticString = #filePath, line: UInt = #line) throws {
        let url = try archive(entries)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try ExtensionArchive.prepare(url), file: file, line: line)
    }

    /// Minimal stored ZIP writer: the tests control names and UNIX entry types
    /// directly without trusting a CLI to sanitize malicious fixtures for us.
    private func archive(_ entries: [Entry]) throws -> URL {
        var local = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.path.utf8)
            let offset = UInt32(local.count)
            let size = entry.declaredSize ?? UInt32(entry.data.count)
            let crc = crc32(entry.data)
            local.appendLE(UInt32(0x04034b50))
            local.appendLE(UInt16(20)); local.appendLE(entry.flags)
            local.appendLE(UInt16(0)); local.appendLE(UInt16(0)); local.appendLE(UInt16(0))
            local.appendLE(crc); local.appendLE(UInt32(entry.data.count)); local.appendLE(size)
            local.appendLE(UInt16(name.count)); local.appendLE(UInt16(0))
            local.append(name); local.append(entry.data)

            central.appendLE(UInt32(0x02014b50))
            central.appendLE(UInt16(0x0314)); central.appendLE(UInt16(20)); central.appendLE(entry.flags)
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(crc); central.appendLE(UInt32(entry.data.count)); central.appendLE(size)
            central.appendLE(UInt16(name.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(entry.mode << 16)
            central.appendLE(offset); central.append(name)
        }
        let centralOffset = UInt32(local.count)
        local.append(central)
        local.appendLE(UInt32(0x06054b50)); local.appendLE(UInt16(0)); local.appendLE(UInt16(0))
        local.appendLE(UInt16(entries.count)); local.appendLE(UInt16(entries.count))
        local.appendLE(UInt32(central.count)); local.appendLE(centralOffset); local.appendLE(UInt16(0))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try local.write(to: url)
        return url
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xedb88320) }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ number: T) {
        var little = number.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
