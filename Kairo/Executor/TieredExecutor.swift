import Foundation

@MainActor
final class TieredExecutor {
    private var tools: [String: Tool] = [:]
    let permissionGate: PermissionGate

    init(permissionGate: PermissionGate) { self.permissionGate = permissionGate }

    func register(_ tool: Tool) { tools[tool.name] = tool }

    func run(toolName: String, args: [String: Any]) async throws -> ToolResult {
        guard let tool = tools[toolName] else {
            return ToolResult(success: false, output: "Unknown tool: \(toolName)", tierUsed: .native)
        }
        guard await permissionGate.allow(tool: tool, args: args) else {
            return ToolResult(success: false, output: "Permission denied", tierUsed: .native)
        }
        for tier in tool.supportedTiers.sorted() {
            do {
                let result = try await tool.execute(tier: tier, args: args)
                if result.success {
                    print("[Kairo] \(toolName) succeeded via \(tier)")
                    return result
                }
            } catch {
                print("[Kairo] \(toolName) tier \(tier) failed: \(error)")
                continue
            }
        }
        return ToolResult(success: false, output: "All tiers exhausted", tierUsed: .uiAutomation)
    }
}
