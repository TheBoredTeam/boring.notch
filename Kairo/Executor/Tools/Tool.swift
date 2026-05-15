import Foundation

protocol Tool {
    var name: String { get }
    var description: String { get }
    var permissionTier: PermissionTier { get }
    var supportedTiers: [ExecutionTier] { get }
    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult
}

struct ToolResult {
    let success: Bool
    let output: String
    let tierUsed: ExecutionTier
}

enum PermissionTier { case safe, destructive, critical }
