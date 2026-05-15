import Foundation

struct SmartHomeTool: Tool {
    let name = "smart_home"
    let description = "Controls lights, scenes, and devices"
    let permissionTier: PermissionTier = .safe
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let device = args["device"] as? String ?? ""
        let action = args["action"] as? String ?? ""
        return ToolResult(success: true, output: "\(action) \(device)", tierUsed: .native)
    }
}
