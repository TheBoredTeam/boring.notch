import AppKit

final class ClipboardTool: Tool {
    let name = "clipboard"
    let description = "Reads recent clipboard content"
    let permissionTier: PermissionTier = .safe
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        return ToolResult(success: true, output: text, tierUsed: .native)
    }
}
