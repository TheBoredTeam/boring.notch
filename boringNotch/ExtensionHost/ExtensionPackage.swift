//
//  ExtensionPackage.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import Security

struct ExtensionManifest: Codable, Equatable {
    enum Activation: String, Codable { case always, lockScreen }
    let id: String
    let name: String
    let version: String
    let apiVersion: Int
    var activation: Activation? = nil

    func receivesUpdates(locked: Bool, awake: Bool, sessionActive: Bool, requested: Bool) -> Bool {
        requested && awake && sessionActive && (activation != .lockScreen || locked)
    }

    func validate() throws {
        guard apiVersion == 1, !name.isEmpty, !version.isEmpty,
              id.range(of: #"^[a-z][a-z0-9]*(\.[a-z0-9-]+)+$"#, options: .regularExpression) != nil
        else { throw ExtensionError.invalidPackage }
    }
}

enum ExtensionError: LocalizedError {
    case invalidPackage, untrustedSignature, unapprovedPublisher, incompatibleBinary, restartRequired

    var errorDescription: String? {
        switch self {
        case .invalidPackage: "This is not a compatible Boring Notch extension."
        case .untrustedSignature: "This extension needs a valid, notarized Developer ID signature."
        case .unapprovedPublisher: "Review this extension's publisher before enabling it."
        case .incompatibleBinary: "This extension could not be loaded. Check its version and Mac compatibility."
        case .restartRequired: "Restart Boring Notch to finish changing this extension."
        }
    }
}

enum ExtensionPackage {
    static func inspect(_ url: URL) throws -> (ExtensionManifest, URL) {
        guard url.pathExtension == "bnplugin" else { throw ExtensionError.invalidPackage }
        let root = url.standardizedFileURL
        // Packages cannot contain symlinks or executable paths
        // outside the signed bundle. The plugin is a single self-contained binary.
        guard let entries = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey]) else {
            throw ExtensionError.invalidPackage
        }
        var bytes = 0
        for case let entry as URL in entries {
            let values = try entry.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            bytes += values.fileSize ?? 0
            guard values.isSymbolicLink != true, bytes < 100_000_000 else {
                throw ExtensionError.invalidPackage
            }
        }
        let rootValues = try root.resourceValues(forKeys: [.isSymbolicLinkKey])
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("Contents/Info.plist")), format: nil)
        guard rootValues.isSymbolicLink != true, let info = info as? [String: Any],
              let executableName = info["CFBundleExecutable"] as? String,
              executableName.range(of: #"^[A-Za-z0-9_-][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil
        else { throw ExtensionError.invalidPackage }
        let executable = root.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
        guard try executable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw ExtensionError.invalidPackage
        }
        let manifest = try JSONDecoder().decode(ExtensionManifest.self,
            from: Data(contentsOf: root.appendingPathComponent("Contents/Resources/manifest.json")))
        try manifest.validate()
        guard info["CFBundleIdentifier"] as? String == manifest.id else { throw ExtensionError.invalidPackage }
        return (manifest, executable)
    }

    static let publisherRequirement = "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and notarized"

    @discardableResult
    static func verifySignature(at url: URL) throws -> ExtensionPublisher {
        #if DEBUG
        // Local development is explicit and unavailable in Release builds.
        if ProcessInfo.processInfo.environment["BN_ALLOW_DEVELOPMENT_EXTENSIONS"] == "1" {
            return ExtensionPublisher(teamID: "development", name: "Local development build", isDevelopment: true)
        }
        #endif
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(publisherRequirement as CFString, [], &requirement) == errSecSuccess,
              let requirement else { throw ExtensionError.untrustedSignature }
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), requirement) == errSecSuccess
        else { throw ExtensionError.untrustedSignature }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess
        else { throw ExtensionError.untrustedSignature }
        guard let values = information as? [String: Any],
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else {
            throw ExtensionError.untrustedSignature
        }
        let certificates = values[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let name = certificates?.first.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? team
        return ExtensionPublisher(teamID: team, name: name, isDevelopment: false)
    }
}

struct ExtensionPublisher: Equatable {
    let teamID: String
    let name: String
    let isDevelopment: Bool
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
