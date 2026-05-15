import Foundation

struct SearchTool: Tool {
    let name = "web_search"
    let description = "Searches the web and returns results"
    let permissionTier: PermissionTier = .safe
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let query = args["query"] as? String ?? ""
        return ToolResult(success: true, output: "stub results for: \(query)", tierUsed: .native)
    }
}
