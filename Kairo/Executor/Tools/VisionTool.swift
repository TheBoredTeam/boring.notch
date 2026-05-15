import Foundation

/// Asks a multimodal LLM (Claude 3.5 Sonnet) about what's currently on screen.
///
/// Args:
///   question: String — the question to ask about the screen
///
/// Used when the user says "this", "what I'm looking at", or anytime the
/// agent needs to see something visual on screen. Falls back to a clean
/// error when ANTHROPIC_API_KEY isn't set, so the ReAct loop can route
/// around (often to `see_screen` for plain OCR).
struct VisionTool: Tool {
    let name = "vision"
    let description = "Captures the screen and asks Claude (multimodal) about it"
    let permissionTier: PermissionTier = .safe
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let question = (args["question"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard await KairoVisionClient.shared.isConfigured else {
            return ToolResult(
                success: false,
                output: "Vision unavailable — set ANTHROPIC_API_KEY in ~/.kairo.env, or use see_screen for plain OCR.",
                tierUsed: .native
            )
        }

        do {
            let answer = try await KairoVisionClient.shared.ask(question: question)
            return ToolResult(success: true, output: answer, tierUsed: .native)
        } catch {
            return ToolResult(success: false, output: error.localizedDescription, tierUsed: .native)
        }
    }
}
