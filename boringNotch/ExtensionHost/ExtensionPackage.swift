//
//  ExtensionPackage.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import Security

struct ExtensionManifest: Codable, Equatable {
    let id: String
    let name: String
    let version: String
    let apiVersion: Int

    func validate() throws {
        guard apiVersion == 1, !name.isEmpty, !version.isEmpty,
              id.range(of: #"^[a-z][a-z0-9]*(\.[a-z0-9-]+)+$"#, options: .regularExpression) != nil
        else { throw ExtensionError.invalidPackage }
    }
}

enum ExtensionError: LocalizedError {
    case invalidPackage, untrustedSignature, incompatibleBinary, restartRequired

    var errorDescription: String? {
        switch self {
        case .invalidPackage: "This is not a compatible Boring Notch extension."
        case .untrustedSignature: "This extension must be signed by the same developer as Boring Notch."
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

    static func verifySignature(at url: URL) throws {
        #if DEBUG
        // Explicit local opt-in; compiled out of release builds. Never change library validation.
        if ProcessInfo.processInfo.environment["BN_ALLOW_DEVELOPMENT_EXTENSIONS"] == "1" { return }
        #endif
        guard let team = try signingTeam(at: Bundle.main.bundleURL), !team.isEmpty,
              try signingTeam(at: url) == team else { throw ExtensionError.untrustedSignature }
    }

    private static func signingTeam(at url: URL) throws -> String? {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { throw ExtensionError.untrustedSignature }
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), requirement) == errSecSuccess
        else { throw ExtensionError.untrustedSignature }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess
        else { throw ExtensionError.untrustedSignature }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
