import Foundation
import AppKit

/// What the PerceptionEngine returns to the Agent Core when asked "what's
/// the user looking at?". Matches the Tech-Spec schema.
public struct PerceptionContext: Codable {
    public let activeAppName: String
    public let activeAppBundleID: String?
    public let activeWindowTitle: String?
    public let screenSummary: String           // short LLM-friendly summary
    public let relevantUIElements: [UIElementDescription]
    public let screenshotPath: String?         // optional file path of captured frame
    public let timestamp: Date
}

/// Simplified description of one accessible UI element on screen.
public struct UIElementDescription: Codable {
    public let id: String              // synthesized — "tree path" e.g. "0.2.4.1"
    public let role: String            // AX role: "AXButton", "AXTextField", "AXStaticText", ...
    public let title: String?          // accessibility label / button title
    public let value: String?          // current value (text field contents, etc.)
    public let frame: CGRect           // window-local position
    public let isInteractable: Bool    // can the user click/type into it
    public let children: Int           // number of children (for orientation, not full subtree)

    /// Compact one-line representation for LLM injection.
    public var summary: String {
        var bits: [String] = []
        bits.append(role.replacingOccurrences(of: "AX", with: ""))
        if let title, !title.isEmpty { bits.append("\"\(title)\"") }
        if let value, !value.isEmpty, value != title { bits.append("=\(value)") }
        if isInteractable { bits.append("•click") }
        return bits.joined(separator: " ")
    }
}
