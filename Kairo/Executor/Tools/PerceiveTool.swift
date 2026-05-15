import Foundation

/// `perceive` — reads the focused app's accessibility tree and returns a
/// compact JSON snapshot for the LLM.
///
/// Args:
///   query: String — optional filter; only UI elements whose title/value/role
///          contains this substring (case-insensitive) are returned
///
/// Returns:
///   A short header line — "App: Safari — Window: ... — Visible: ..."
///   followed by a JSON array of `UIElementDescription` entries.
///
/// Privacy: Requires the user to have granted Kairo "Accessibility"
/// permission (System Settings → Privacy & Security → Accessibility).
/// Without that, the tool returns a clear message explaining how to enable.
///
/// This is the macOS equivalent of the iOS AXUIElement perception in the
/// Tech-Spec — same name, different framework (`ApplicationServices`).
struct PerceiveTool: Tool {
    let name = "perceive"
    let description = "Reads the focused app's UI tree via macOS Accessibility"
    let permissionTier: PermissionTier = .safe
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let query = (args["query"] as? String).flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        }

        let context = await KairoPerceptionEngine.shared.perceive(query: query)

        // Encode the elements as JSON so the LLM gets structured data.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let elementsJSON: String
        if let data = try? encoder.encode(context.relevantUIElements),
           let s = String(data: data, encoding: .utf8) {
            elementsJSON = s
        } else {
            elementsJSON = "[]"
        }

        let body = "\(context.screenSummary)\n\nELEMENTS:\n\(elementsJSON)"
        return ToolResult(success: true, output: body, tierUsed: .native)
    }
}
