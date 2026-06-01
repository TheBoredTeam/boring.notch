//  CodeSigningStatus.swift
//  IslandNotch
//
//  Purpose: Detects whether the running binary is ad-hoc signed (TCC grants reset
//           every rebuild) or signed with a stable certificate.
//  Layer: Support

import Foundation
import Security

enum CodeSigningStatus {
    /// True when the app is ad-hoc signed — macOS TCC grants reset on every rebuild.
    static var isAdHocSigned: Bool {
        guard let url = Bundle.main.executableURL else { return true }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return true }

        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInfo
        ) == errSecSuccess,
            let info = signingInfo as? [String: Any] else { return true }

        if let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return false
        }
        if let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate], !certs.isEmpty {
            return false
        }
        return true
    }

    /// Human-readable signing authority, when available.
    static var authoritySummary: String? {
        guard let url = Bundle.main.executableURL else { return nil }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }

        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInfo
        ) == errSecSuccess,
            let info = signingInfo as? [String: Any] else { return nil }

        if let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let first = certs.first {
            var summary: CFString?
            if SecCertificateCopyCommonName(first, &summary) == errSecSuccess,
               let name = summary as String?, !name.isEmpty {
                return name
            }
        }
        return nil
    }
}
