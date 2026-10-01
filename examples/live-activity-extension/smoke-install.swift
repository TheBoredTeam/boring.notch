// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

// Compiled with the actual host installer/runtime; no Boring Notch app launches.

import AppKit
import Combine
import Foundation

/// The manager's only app-specific dependency. No player, XPC, permissions,
/// window manager, user preferences, or hardware monitor starts in this test.
@MainActor
final class MusicManager: ObservableObject {
    static let shared = MusicManager()
    let songTitle = "Installer smoke test"
    let artistName = "Local fixture"
    let album = ""
    let songDuration = 60.0
    let playbackRate = 0.0
    let isPlaying = false
    let isPlayerIdle = true
    let isFavoriteTrack = false
    let canFavoriteTrack = false
    let albumArt = NSImage(size: NSSize(width: 1, height: 1))
    func estimatedPlaybackPosition() -> Double { 0 }
    func playPause() {}
    func nextTrack() {}
    func previousTrack() {}
    func toggleFavoriteTrack() {}
    func seek(to: Double) {}
}

@main
struct InstallSmoke {
    @MainActor
    static func main() async throws {
        guard (2...3).contains(CommandLine.arguments.count),
              let directory = ProcessInfo.processInfo.environment["BN_EXTENSION_TEST_DIRECTORY"],
              ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] != nil,
              ProcessInfo.processInfo.environment["BN_ALLOW_DEVELOPMENT_EXTENSIONS"] == "1" else {
            throw Failure("Run smoke-install.sh to provide isolated installation and preferences directories.")
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        if CommandLine.arguments.last == "--external-replacement" {
            try verifyExternalReplacementRequiresRestart(source, directory: URL(fileURLWithPath: directory).deletingLastPathComponent())
            print("PASS: external replacement CDHash protection requires restart.")
            return
        }
        let manager = ExtensionManager.shared
        manager.start()
        defer { manager.stop() }
        try require(manager.installed.isEmpty, "The isolated extension directory was not empty.")

        manager.install(from: source)
        try await finishInstall(manager)
        let manifest = try unwrap(manager.installed.first, "The ZIP did not install: \(manager.message ?? "no message")")
        try require(manager.installed.count == 1, "Expected one installed package.")
        try require(manager.enabledIDs.contains(manifest.id), "Installed extension was not enabled.")
        try require(hasActivity(manifest.id), "Installed extension did not publish through the real service.")
        try require(hasTab(manifest.id), "Installed extension did not publish its native tab after opting out of media.")
        try require(hasCompactTab(manifest.id), "Installed v2 extension did not expose its declared compact tab.")

        let wrongRequirements = [
            ExtensionInstallation.Requirement(id: "org.example.wrong", version: manifest.version, publisherTeamID: "development"),
            ExtensionInstallation.Requirement(id: manifest.id, version: "wrong-version", publisherTeamID: "development"),
            ExtensionInstallation.Requirement(id: manifest.id, version: manifest.version, publisherTeamID: "WRONGTEAM1")
        ]
        for requirement in wrongRequirements {
            var completed = false
            manager.install(from: source, expected: requirement) { completed = true }
            try await finishInstall(manager)
            try require(completed, "Rejected catalog identity did not complete the installation request.")
            try require(manager.enabledIDs.contains(manifest.id) && hasActivity(manifest.id) && hasTab(manifest.id) && !manager.needsRestart,
                        "A mismatched catalog identity replaced or interrupted the installed extension.")
        }

        // A failed signature check must leave the installed code and instance
        // intact. The added resource is deliberately outside the signed seal.
        let tampered = URL(fileURLWithPath: directory).deletingLastPathComponent()
            .appendingPathComponent("tampered.bnplugin")
        try ExtensionArchive.withPreparedPackage(at: source) {
            try FileManager.default.copyItem(at: $0, to: tampered)
        }
        try Data("unsigned resource".utf8).write(to:
            tampered.appendingPathComponent("Contents/Resources/unsealed.txt"))
        manager.install(from: tampered)
        try await finishInstall(manager)
        try require(manager.enabledIDs.contains(manifest.id) && hasActivity(manifest.id) && hasTab(manifest.id),
                    "Rejected package interrupted the installed extension.")
        try require(!manager.needsRestart, "Rejected package changed the restart state.")
        _ = try ExtensionPackage.verifySignature(at: URL(fileURLWithPath: directory)
            .appendingPathComponent(manifest.id + ".bnplugin"))

        manager.disable(manifest)
        try await settle()
        try require(!manager.enabledIDs.contains(manifest.id), "Disable left the runtime enabled.")
        try require(!hasActivity(manifest.id), "Disable did not withdraw the activity.")
        try require(!hasTab(manifest.id), "Disable did not withdraw the tab.")

        manager.enable(manifest)
        try await settle()
        try require(manager.enabledIDs.contains(manifest.id), "Enable did not create a fresh instance.")
        try require(hasActivity(manifest.id), "The fresh instance did not publish its activity.")
        try require(hasTab(manifest.id), "The fresh instance did not publish its tab.")
        try require(hasCompactTab(manifest.id), "The fresh instance lost its compact tab support.")

        manager.install(from: source)
        try await finishInstall(manager)
        try require(manager.needsRestart, "Updating loaded Swift code did not require restart.")
        try require(!manager.enabledIDs.contains(manifest.id), "Update left the old instance enabled.")
        try require(!hasActivity(manifest.id), "Update left the old activity registered.")
        try require(!hasTab(manifest.id), "Update left the old tab registered.")
        manager.enable(manifest)
        try await settle()
        try require(!manager.enabledIDs.contains(manifest.id), "Updated code was enabled without restart.")

        manager.remove(manifest)
        try await settle()
        try require(manager.installed.isEmpty, "Uninstall did not refresh the installed package list.")
        try require(!hasActivity(manifest.id), "Uninstall left an activity registered.")
        try require(!hasTab(manifest.id), "Uninstall left a tab registered.")
        try require(!FileManager.default.fileExists(atPath:
            URL(fileURLWithPath: directory).appendingPathComponent(manifest.id + ".bnplugin").path),
            "Uninstall left the bundle in the installation directory.")
        print("PASS: ZIP install, signed load, ID/version/publisher pinning, tamper rejection preserving installed code, activity/tab publication with media opt-out, disable, fresh enable, update/restart, and uninstall.")
    }

    @MainActor private static func hasActivity(_ namespace: String) -> Bool {
        LiveActivityCenter.shared.service.snapshot(in: LiveActivityContext(displayID: "smoke-display"))
            .activities.contains { $0.id.namespace == namespace }
    }

    @MainActor private static func hasTab(_ providerID: String) -> Bool {
        ExtensionTabRegistry.shared.tabs.contains { $0.id.providerID == providerID }
    }

    @MainActor private static func hasCompactTab(_ providerID: String) -> Bool {
        ExtensionTabRegistry.shared.tabs(for: .compact).contains { $0.id.providerID == providerID }
    }

    @MainActor private static func finishInstall(_ manager: ExtensionManager) async throws {
        let deadline = Date().addingTimeInterval(20)
        while manager.isInstalling, Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        try require(!manager.isInstalling, "Installer did not finish within 20 seconds.")
        try await settle()
    }

    private static func settle() async throws { try await Task.sleep(for: .milliseconds(100)) }

    @MainActor private static func verifyExternalReplacementRequiresRestart(_ source: URL, directory: URL) throws {
        let original = directory.appendingPathComponent("external.bnplugin")
        let replacement = directory.appendingPathComponent("replacement.bnplugin")
        try ExtensionArchive.withPreparedPackage(at: source) { prepared in
            try FileManager.default.copyItem(at: prepared, to: original)
            try FileManager.default.copyItem(at: prepared, to: replacement)
        }
        let runtime = try ExtensionRuntime(url: original) { _, _, _ in }
        runtime.stop()
        let before = try ExtensionPackage.verifySignature(at: original).codeHash
        try Data("new signed resource".utf8).write(to:
            replacement.appendingPathComponent("Contents/Resources/replacement.txt"))
        let signer = Process()
        signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signer.arguments = ["--force", "--sign", "-", replacement.path]
        try signer.run()
        signer.waitUntilExit()
        try require(signer.terminationStatus == 0, "Could not sign the external replacement fixture.")
        let after = try ExtensionPackage.verifySignature(at: replacement).codeHash
        try require(before != nil && after != nil && before != after, "Fixture did not change signed code identity.")
        _ = try FileManager.default.replaceItemAt(original, withItemAt: replacement)
        do {
            let unexpected = try ExtensionRuntime(url: original) { _, _, _ in }
            unexpected.stop()
            throw Failure("External code replacement loaded without an app restart.")
        } catch ExtensionError.restartRequired {
            // Expected: dyld's existing image must not run under new metadata.
        }
    }

    private static func require(_ value: Bool, _ message: String) throws {
        if !value { throw Failure(message) }
    }
    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw Failure(message) }
        return value
    }
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
