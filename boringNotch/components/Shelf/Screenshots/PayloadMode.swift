//
//  PayloadMode.swift
//  boringNotch
//
//  Purpose: How a screenshot is placed on the clipboard so a given CLI agent
//           can ingest it. The file path is the entire integration contract.
//  Layer: Model
//

import Foundation
import Defaults

/// The clipboard representation used when copying a screenshot for an agent.
enum PayloadMode: String, Codable, CaseIterable, Identifiable, Defaults.Serializable {
    /// Absolute POSIX path as plain text, e.g. "/Users/me/Desktop/boring-shots/x.png".
    case pathPlain
    /// Absolute path prefixed with "look at " so it reads as a prompt line.
    case pathLookAtPrefixed
    /// The image bytes themselves (for harnesses that only accept pasted images).
    case imageBytes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pathPlain: return "File path"
        case .pathLookAtPrefixed: return "“look at <path>”"
        case .imageBytes: return "Image bytes"
        }
    }

    var explanation: String {
        switch self {
        case .pathPlain:
            return "Copies the absolute file path. Paste it into the agent; most CLI agents read the path as an image."
        case .pathLookAtPrefixed:
            return "Copies “look at <path>” so it reads as a natural instruction line."
        case .imageBytes:
            return "Copies the raw image. Use for harnesses that only accept a pasted image, not a path."
        }
    }
}
