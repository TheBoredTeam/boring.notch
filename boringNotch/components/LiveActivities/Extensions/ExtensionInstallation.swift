// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Foundation

/// Filesystem work is separate from publisher review and the running plugin.
/// A failed extraction, copy, or verification cannot replace the installed bundle.
enum ExtensionInstallation {
    /// A reviewed catalog release pins identity as well as the download digest.
    /// Price and licensing are deliberately absent from the installation contract.
    struct Requirement: Equatable, Sendable {
        let id: String
        let version: String
        let publisherTeamID: String
    }

    struct StagedPackage: Sendable {
        let url: URL
        let manifest: ExtensionManifest
        let publisher: ExtensionPublisher

        func cleanup() { try? FileManager.default.removeItem(at: url) }
    }

    static func stage(source: URL, directory: URL, expected: Requirement? = nil) throws -> StagedPackage {
        let prepared = try ExtensionArchive.prepare(source)
        defer { prepared.cleanup() }
        let (manifest, _) = try ExtensionPackage.inspect(prepared.url)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent("\(UUID().uuidString).bnplugin")
        do {
            try FileManager.default.copyItem(at: prepared.url, to: staging)
            let (stagedManifest, _) = try ExtensionPackage.inspect(staging)
            guard stagedManifest == manifest else { throw ExtensionError.invalidPackage }
            let publisher = try ExtensionPackage.verifySignature(at: staging)
            if let expected {
                guard manifest.id == expected.id, manifest.version == expected.version,
                      publisher.teamID == expected.publisherTeamID else { throw ExtensionError.unexpectedPackage }
            }
            return StagedPackage(url: staging, manifest: manifest, publisher: publisher)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }
}
