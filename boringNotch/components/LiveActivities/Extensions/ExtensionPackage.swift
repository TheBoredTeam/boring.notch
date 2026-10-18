// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

//
//  ExtensionPackage.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import Security

struct ExtensionManifest: Codable, Equatable, Sendable {
    enum Activation: String, Codable, Sendable { case always, lockScreen }
    let id: String
    let name: String
    let version: String
    let apiVersion: Int
    var activation: Activation? = nil
    /// Optional ABI additions; older packages remain valid without capabilities.
    var capabilities: [String]? = nil

    func receivesUpdates(locked: Bool, awake: Bool, sessionActive: Bool, requested: Bool) -> Bool {
        requested && awake && sessionActive && (activation != .lockScreen || locked)
    }

    func validate() throws {
        guard apiVersion == 1, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf8.count <= 128, !version.isEmpty, version.utf8.count <= 64,
              id.utf8.count <= 128, (capabilities?.count ?? 0) <= 16,
              capabilities?.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 64 }) != false,
              id.range(of: #"\A[a-z][a-z0-9]*(\.[a-z0-9-]+)+\z"#, options: .regularExpression) != nil
        else { throw ExtensionError.invalidPackage }
    }
}

enum ExtensionError: LocalizedError {
    case invalidPackage, invalidArchive, archiveTooLarge, untrustedSignature, unapprovedPublisher, incompatibleBinary, restartRequired
    case unexpectedPackage

    var errorDescription: String? {
        switch self {
        case .invalidPackage: "This is not a compatible Boring Notch extension."
        case .invalidArchive: "Choose a ZIP containing one .bnplugin bundle. Links, encrypted entries, and unsafe paths are not supported."
        case .archiveTooLarge: "This extension exceeds the installation limit of 100 MB or 4,096 files."
        case .untrustedSignature: "This extension needs a valid, notarized Developer ID signature."
        case .unapprovedPublisher: "Review this extension's publisher before enabling it."
        case .incompatibleBinary: "This extension could not be loaded. Check its version and Mac compatibility."
        case .restartRequired: "Restart Boring Notch to finish changing this extension."
        case .unexpectedPackage: "The downloaded bundle does not match the extension, version, or publisher reviewed for this release."
        }
    }
}

enum ExtensionPackage {
    static let maximumBytes = 100_000_000
    static let maximumEntries = 4_096

    static func inspect(_ url: URL) throws -> (ExtensionManifest, URL) {
        guard url.pathExtension == "bnplugin" else { throw ExtensionError.invalidPackage }
        let root = url.standardizedFileURL
        // Packages cannot contain symlinks or executable paths
        // outside the signed bundle. The plugin is a single self-contained binary.
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        let rootValues = try root.resourceValues(forKeys: keys)
        var enumerationFailed = false
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true,
              let entries = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: Array(keys), errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }) else {
            throw ExtensionError.invalidPackage
        }
        var bytes = 0
        var count = 0
        for case let entry as URL in entries {
            let values = try entry.resourceValues(forKeys: keys)
            count += 1
            guard values.isSymbolicLink != true,
                  values.isRegularFile == true || values.isDirectory == true else {
                throw ExtensionError.invalidPackage
            }
            let size = values.isRegularFile == true ? values.fileSize ?? 0 : 0
            guard size >= 0, size <= maximumBytes - bytes, count <= maximumEntries else {
                throw ExtensionError.archiveTooLarge
            }
            bytes += size
        }
        guard !enumerationFailed else { throw ExtensionError.invalidPackage }
        let info = try PropertyListSerialization.propertyList(from: metadata(
            at: root.appendingPathComponent("Contents/Info.plist")), format: nil)
        guard let info = info as? [String: Any],
              let executableName = info["CFBundleExecutable"] as? String,
              executableName.utf8.count <= 255,
              executableName.range(of: #"\A[A-Za-z0-9_-][A-Za-z0-9_.-]*\z"#, options: .regularExpression) != nil
        else { throw ExtensionError.invalidPackage }
        let executable = root.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
        guard try executable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw ExtensionError.invalidPackage
        }
        let manifest = try JSONDecoder().decode(ExtensionManifest.self,
            from: metadata(at: root.appendingPathComponent("Contents/Resources/manifest.json")))
        try manifest.validate()
        guard info["CFBundleIdentifier"] as? String == manifest.id else { throw ExtensionError.invalidPackage }
        return (manifest, executable)
    }

    private static func metadata(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let bytes = values.fileSize, bytes <= 65_536 else {
            throw ExtensionError.invalidPackage
        }
        return try Data(contentsOf: url)
    }

    static let publisherRequirement = "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and notarized"

    @discardableResult
    static func verifySignature(at url: URL) throws -> ExtensionPublisher {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code else { throw ExtensionError.untrustedSignature }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        #if DEBUG
        // Development still requires an intact signature (including ad-hoc).
        // This opt-in is absent from Release builds.
        if ProcessInfo.processInfo.environment["BN_ALLOW_DEVELOPMENT_EXTENSIONS"] == "1" {
            guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else {
                throw ExtensionError.untrustedSignature
            }
            return ExtensionPublisher(teamID: "development", name: "Local development build", isDevelopment: true,
                                      codeHash: try signingInformation(code)[kSecCodeInfoUnique as String] as? Data)
        }
        #endif
        guard SecRequirementCreateWithString(publisherRequirement as CFString, [], &requirement) == errSecSuccess,
              let requirement else { throw ExtensionError.untrustedSignature }
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
        else { throw ExtensionError.untrustedSignature }
        let values = try signingInformation(code)
        guard let team = values[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else {
            throw ExtensionError.untrustedSignature
        }
        let certificates = values[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let name = certificates?.first.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? team
        return ExtensionPublisher(teamID: team, name: name, isDevelopment: false,
                                  codeHash: values[kSecCodeInfoUnique as String] as? Data)
    }

    private static func signingInformation(_ code: SecStaticCode) throws -> [String: Any] {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else { throw ExtensionError.untrustedSignature }
        return values
    }
}

struct ExtensionPublisher: Equatable, Sendable {
    let teamID: String
    let name: String
    let isDevelopment: Bool
    var codeHash: Data? = nil
}

/// Approval is for a specific extension ID and publisher, never payment status.
enum ExtensionTrustStore {
    private static let key = "approvedExtensionPublishers"
    static func isApproved(_ publisher: ExtensionPublisher, for id: String, defaults: UserDefaults = .standard) -> Bool {
        publisher.isDevelopment || (defaults.dictionary(forKey: key) as? [String: String])?[id] == publisher.teamID
    }
    static func approve(_ publisher: ExtensionPublisher, for id: String, defaults: UserDefaults = .standard) {
        guard !publisher.isDevelopment else { return }
        var publishers = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        publishers[id] = publisher.teamID
        defaults.set(publishers, forKey: key)
    }
    static func remove(_ id: String, defaults: UserDefaults = .standard) {
        var publishers = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        publishers.removeValue(forKey: id)
        defaults.set(publishers, forKey: key)
    }
}
